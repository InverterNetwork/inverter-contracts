// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../deployment/DeployLocal.s.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {IOrchestratorFactory} from "src/factories/IOrchestratorFactory.sol";
import {IOrchestrator} from "src/orchestrator/Orchestrator.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {ScriptConstants} from "../script-constants.sol";
import {RebasingFundingManager} from
    "src/modules/fundingManager/RebasingFundingManager.sol";

contract SetupLocalToyOrchestratorScript is Test, DeployLocal {
    ScriptConstants scriptConstants = new ScriptConstants();
    bool hasDependency;
    string[] dependencies = new string[](0);

    // ------------------------------------------------------------------------
    // Fetch Environment Variables
    uint deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    //-------------------------------------------------------------------------
    // Mock Funder and Contributor information

    //Since this is a demo deployment, we will use the same address for the owner and the funder.
    uint funder1PrivateKey = deployerPrivateKey;
    address funder1 = deployer;

    //-------------------------------------------------------------------------
    // Storage

    ERC20Mock token;
    IOrchestrator test_orchestrator;

    address[] initialAuthorizedAddresses;

    //-------------------------------------------------------------------------
    // Script

    function run() public override returns (address deployedOrchestrator) {
        // ------------------------------------------------------------------------
        // Setup

        // First we deploy a mock ERC20 to act as funding token for the orchestrator. It has a public mint function.
        vm.startBroadcast(deployerPrivateKey);
        {
            token = new ERC20Mock("Inverter USD", "iUSD");
        }
        vm.stopBroadcast();
        //token = ERC20Mock(0x5eb14c2e7D0cD925327d74ae4ce3fC692ff8ABEF);

        // Then, we run the deployment script to deploy the factories, implementations and Beacons.
        address orchestratorFactory = DeployLocal.run();

        //We use the exisiting orchestratorFactory address
        //address orchestratorFactory = 0x690d5000D278f90B167354975d019c747B78032e;

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Orchestrator: Owner, funding token
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({owner: deployer, token: token});

        // Funding Manager: Metadata, token address
        IOrchestratorFactory.ModuleConfig memory fundingManagerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            rebasingFundingManagerMetadata,
            abi.encode(address(token)),
            abi.encode(hasDependency, dependencies)
        );

        // Payment Processor: only Metadata
        IOrchestratorFactory.ModuleConfig memory paymentProcessorFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            simplePaymentProcessorMetadata,
            bytes(""),
            abi.encode(hasDependency, dependencies)
        );

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            roleAuthorizerMetadata,
            abi.encode(deployer, deployer),
            abi.encode(hasDependency, dependencies)
        );

        // MilestoneManager: Metadata, salary precision, fee percentage, fee treasury address
        IOrchestratorFactory.ModuleConfig memory bountyManagerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            bountyManagerMetadata,
            abi.encode(""),
            abi.encode(true, dependencies)
        );

        // Add the configuration for all the non-mandatory modules. In this case only the BountyManager.
        IOrchestratorFactory.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory.ModuleConfig[](1);
        additionalModuleConfig[0] = bountyManagerFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator Creation

        vm.startBroadcast(deployerPrivateKey);
        {
            test_orchestrator = IOrchestratorFactory(orchestratorFactory)
                .createOrchestrator(
                orchestratorConfig,
                fundingManagerFactoryConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Check if the orchestrator has been created correctly.

        assert(address(test_orchestrator) != address(0));

        address orchestratorToken =
            address(IOrchestrator(test_orchestrator).fundingManager().token());
        assertEq(orchestratorToken, address(token));

        // Now we need to find the MilestoneManager. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the MilestoneManager.

        // TODO: Ideally this would be substituted by a check that that all mandatory modules implement their corresponding interfaces + the same for MilestoneManager

        address[] memory moduleAddresses =
            IOrchestrator(test_orchestrator).listModules();
        uint lenModules = moduleAddresses.length;
        address orchestratorCreatedBountyManagerAddress;

        for (uint i; i < lenModules;) {
            try IBountyManager(moduleAddresses[i]).isExistingBountyId(0)
            returns (bool) {
                orchestratorCreatedBountyManagerAddress = moduleAddresses[i];
                break;
            } catch {
                i++;
            }
        }

        BountyManager orchestratorCreatedBountyManager =
            BountyManager(orchestratorCreatedBountyManagerAddress);

        assertEq(
            address(orchestratorCreatedBountyManager.orchestrator()),
            address(test_orchestrator)
        );

        assertFalse(
            orchestratorCreatedBountyManager.isExistingBountyId(0),
            "Error in the BountyManager"
        );
        assertFalse(
            orchestratorCreatedBountyManager.isExistingBountyId(type(uint).max),
            "Error in the BountyManager"
        );

        console2.log("\n\n");
        console2.log(
            "=================================================================================="
        );
        console2.log(
            "Orchestrator with Id %s created at address: %s ",
            test_orchestrator.orchestratorId(),
            address(test_orchestrator)
        );
        console2.log(
            "\t-FundingManager deployed at address: %s ",
            address(test_orchestrator.fundingManager())
        );
        console2.log(
            "\t-Authorizer deployed at address: %s ",
            address(test_orchestrator.authorizer())
        );
        console2.log(
            "\t-PaymentProcessor deployed at address: %s ",
            address(test_orchestrator.paymentProcessor())
        );

        console2.log(
            "\t-BountyManager deployed at address: %s ",
            address(orchestratorCreatedBountyManager)
        );
        console2.log(
            "=================================================================================="
        );

        // ------------------------------------------------------------------------
        // Initialize FundingManager

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the orchestrator.
        // It's best, if the owner deposits them right after deployment.

        // Initial Deposit => 10e18;
        RebasingFundingManager fundingManager =
            RebasingFundingManager(address(test_orchestrator.fundingManager()));

        vm.startBroadcast(deployerPrivateKey);
        {
            token.mint(
                address(deployer),
                scriptConstants.orchestratorTokenDepositAmount()
            );

            token.approve(
                address(fundingManager),
                scriptConstants.orchestratorTokenDepositAmount()
            );

            fundingManager.deposit(
                scriptConstants.orchestratorTokenDepositAmount()
            );
        }
        vm.stopBroadcast();
        console2.log("\t -Initialization Funding Done");

        // Mint some tokens for the funder and deposit them
        vm.startBroadcast(funder1PrivateKey);
        {
            token.mint(funder1, scriptConstants.funder1TokenDepositAmount());
            token.approve(
                address(fundingManager),
                scriptConstants.funder1TokenDepositAmount()
            );
            fundingManager.deposit(scriptConstants.funder1TokenDepositAmount());
        }
        vm.stopBroadcast();
        console2.log("\t -Funder 1: Deposit Performed");

        // ------------------------------------------------------------------------

        // Create a Bounty
        vm.startBroadcast(deployerPrivateKey);

        // Whitelist owner to create bounties
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.BOUNTY_ISSUER_ROLE(), deployer
        );

        // Whitelist owner to post claims
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.CLAIMANT_ROLE(), deployer
        );
        // Whitelist owner to verify claims
        orchestratorCreatedBountyManager.grantModuleRole(
            orchestratorCreatedBountyManager.VERIFIER_ROLE(), deployer
        );

        bytes memory details = "TEST BOUNTY";

        uint bountyId = orchestratorCreatedBountyManager.addBounty(
            scriptConstants.addBounty_minimumPayoutAmount(),
            scriptConstants.addBounty_maximumPayoutAmount(),
            details
        );

        vm.stopBroadcast();

        console2.log("\t -Bounty Created. Id: ", bountyId);

        console2.log(
            "=================================================================================="
        );
        console2.log("\n\n");

        return address(test_orchestrator);
    }
}