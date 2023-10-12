// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../../deployment/DeploymentScript.s.sol";

import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IModule} from "src/modules/base/IModule.sol";
import {IOrchestratorFactory} from "src/factories/IOrchestratorFactory.sol";
import {IOrchestrator} from "src/orchestrator/Orchestrator.sol";
import {
    BountyManager,
    IBountyManager
} from "src/modules/logicModule/BountyManager.sol";
import {BancorVirtualSupplyBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/BancorVirtualSupplyBondingCurveFundingManager.sol";

import {BancorFormula} from
    "src/modules/fundingManager/bondingCurveFundingManager/formula/BancorFormula.sol";

import {ERC20} from "@oz/token/ERC20/ERC20.sol";
//import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
//import {ScriptConstants} from "../script-constants.sol";

contract SetupInvestableWorkstream is Test, DeploymentScript {
    //ScriptConstants scriptConstants = new ScriptConstants();
    bool hasDependency;
    string[] dependencies = new string[](0);

    // ========================================================================
    // ENVIRONMENT VARIABLES OR CONSTANTS

    uint orchestratorOwnerPrivateKey =
        vm.envUint("ORCHESTRATOR_OWNER_PRIVATE_KEY");
    address orchestratorOwner = vm.addr(orchestratorOwnerPrivateKey);
    address collateralTokenAddress =
        vm.envAddress("BONDING_CURVE_COLLATERAL_TOKEN");
    ERC20 collateralToken = ERC20(collateralTokenAddress);

    // ========================================================================
    // BONDING CURVE PARAMETERS

    string CURVE_TOKEN_NAME = "Bonding Curve Token";
    string CURVE_TOKEN_SYMBOL = "BCT";
    uint INITIAL_TOKEN_SUPPLY = 1;
    uint INITIAL_COLLATERAL_SUPPLY = 1;
    uint RESERVE_RATIO_FOR_BUYING = 200_000;
    uint RESERVE_RATIO_FOR_SELLING = 200_000;
    uint BUY_FEE = 0;
    uint SELL_FEE = 0;
    bool BUY_IS_OPEN = true;
    bool SELL_IS_OPEN = true;

    // ========================================================================

    //-------------------------------------------------------------------------
    // Storage

    IOrchestrator _orchestrator;

    BancorFormula formula;

    address[] initialAuthorizedAddresses;

    //-------------------------------------------------------------------------
    // Script

    function run() public override returns (address deployedOrchestrator) {
        // ------------------------------------------------------------------------
        // OPTIONAL PRE-STEPS

        //If the factories aren't deployed on the target chain, we can run the deployment script to deploy the factories, implementations and Beacons.
        address orchestratorFactory = DeploymentScript.run();

        //If there's no formula deployment on the chain, we deploy the Bancor Formula
        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            formula = new BancorFormula();
        }
        vm.stopBroadcast();

        // ------------------------------------------------------------------------
        // Setup

        // ------------------------------------------------------------------------
        // Define Initial Configuration Data

        // Orchestrator: Owner, funding token
        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: orchestratorOwner,
            token: collateralToken
        });

        // Funding Manager: Virtual Supply Bonding Curve Funding Manager
        IOrchestratorFactory.ModuleConfig memory
            bondingCurveFundingManagerConfig = IOrchestratorFactory
                .ModuleConfig(
                bondingCurveFundingManagerMetadata,
                abi.encode(
                    CURVE_TOKEN_NAME,
                    CURVE_TOKEN_SYMBOL,
                    address(formula),
                    INITIAL_TOKEN_SUPPLY,
                    INITIAL_TOKEN_SUPPLY,
                    RESERVE_RATIO_FOR_BUYING,
                    RESERVE_RATIO_FOR_SELLING,
                    BUY_FEE,
                    SELL_FEE,
                    BUY_IS_OPEN,
                    SELL_IS_OPEN
                ),
                abi.encode(hasDependency, dependencies)
            );

        // Payment Processor: only Metadata
        IOrchestratorFactory.ModuleConfig memory paymentProcessorFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            paymentProcessorMetadata,
            bytes(""),
            abi.encode(hasDependency, dependencies)
        );

        // Authorizer: Metadata, initial authorized addresses
        IOrchestratorFactory.ModuleConfig memory authorizerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            authorizerMetadata,
            abi.encode(orchestratorOwner, orchestratorOwner),
            abi.encode(hasDependency, dependencies)
        );

        // Bounty Manager:
        IOrchestratorFactory.ModuleConfig memory bountyManagerFactoryConfig =
        IOrchestratorFactory.ModuleConfig(
            bountyManagerMetadata,
            abi.encode(""),
            abi.encode(hasDependency, dependencies)
        );

        // Add the configuration for all the non-mandatory modules. In this case only the BountyManager.
        IOrchestratorFactory.ModuleConfig[] memory additionalModuleConfig =
            new IOrchestratorFactory.ModuleConfig[](1);
        additionalModuleConfig[0] = bountyManagerFactoryConfig;

        // ------------------------------------------------------------------------
        // Orchestrator Creation

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            _orchestrator = IOrchestratorFactory(orchestratorFactory)
                .createOrchestrator(
                orchestratorConfig,
                bondingCurveFundingManagerConfig,
                authorizerFactoryConfig,
                paymentProcessorFactoryConfig,
                additionalModuleConfig
            );
        }
        vm.stopBroadcast();

        // Check if the orchestrator has been created correctly.

        assert(address(_orchestrator) != address(0));

        address orchestratorToken =
            address(IOrchestrator(_orchestrator).token());
        assertEq(orchestratorToken, address(collateralToken));

        // Now we need to find the MilestoneManager. ModuleManager has a function called `listModules` that returns a list of
        // active modules, let's use that to get the address of the MilestoneManager.

        // TODO: Ideally this would be substituted by a check that that all mandatory modules implement their corresponding interfaces + the same for MilestoneManager

        address[] memory moduleAddresses =
            IOrchestrator(_orchestrator).listModules();
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
            address(_orchestrator)
        );

        assertFalse(
            orchestratorCreatedBountyManager.isExistingBountyId(0),
            "Error in the BountyManager"
        );
        assertFalse(
            orchestratorCreatedBountyManager.isExistingBountyId(type(uint).max),
            "Error in the BountyManager"
        );

        assertEq(formula.version(), "0.3");

        console2.log("\n\n");
        console2.log(
            "=================================================================================="
        );
        console2.log(
            "Orchestrator with Id %s created at address: %s ",
            _orchestrator.orchestratorId(),
            address(_orchestrator)
        );
        console2.log(
            "\t-BondingCurveFundingManager deployed at address: %s ",
            address(_orchestrator.fundingManager())
        );
        console2.log(
            "\t-Authorizer deployed at address: %s ",
            address(_orchestrator.authorizer())
        );
        console2.log(
            "\t-PaymentProcessor deployed at address: %s ",
            address(_orchestrator.paymentProcessor())
        );

        console2.log(
            "\t-BountyManager deployed at address: %s ",
            address(orchestratorCreatedBountyManager)
        );
        console2.log(
            "=================================================================================="
        );

        // ------------------------------------------------------------------------

        vm.startBroadcast(orchestratorOwnerPrivateKey);
        {
            // Whitelist owner to create bounties
            orchestratorCreatedBountyManager.grantModuleRole(
                orchestratorCreatedBountyManager.BOUNTY_ISSUER_ROLE(),
                orchestratorOwner
            );

            // Whitelist owner to post claims
            orchestratorCreatedBountyManager.grantModuleRole(
                orchestratorCreatedBountyManager.CLAIMANT_ROLE(),
                orchestratorOwner
            );
            // Whitelist owner to verify claims
            orchestratorCreatedBountyManager.grantModuleRole(
                orchestratorCreatedBountyManager.VERIFIER_ROLE(),
                orchestratorOwner
            );
        }
        vm.stopBroadcast();

        console2.log("\t - Initial Roles assigned.");

        console2.log(
            "=================================================================================="
        );
        console2.log("\n\n");

        return address(_orchestrator);
    }
}
