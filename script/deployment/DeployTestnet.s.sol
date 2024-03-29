// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// Import interfaces:

import {IModule} from "src/modules/base/IModule.sol";
import {IModuleFactory} from "src/factories/ModuleFactory.sol";

// Import scripts:

import {DeployAndSetUpBeacon} from "script/proxies/DeployAndSetUpBeacon.s.sol";
import {TransferBeaconOwnership} from
    "script/proxies/TransferBeaconOwnership.s.sol";
import {DeployModuleFactory} from "script/factories/DeployModuleFactory.s.sol";
import {TransferModuleFactoryOwnership} from
    "script/factories/TransferModuleFactoryOwnership.s.sol";
import {DeployOrchestratorFactory} from
    "script/factories/DeployOrchestratorFactory.s.sol";
import {DeployBountyManager} from "script/modules/DeployBountyManager.s.sol";

import {DeployTransactionForwarder} from
    "script/external/DeployTransactionForwarder.s.sol";
import {DeployOrchestrator} from "script/orchestrator/DeployOrchestrator.s.sol";
import {DeploySimplePaymentProcessor} from
    "script/modules/paymentProcessor/DeploySimplePaymentProcessor.s.sol";
import {DeployRebasingFundingManager} from
    "script/modules/fundingManager/DeployRebasingFundingManager.s.sol";
import {DeployRoleAuthorizer} from
    "script/modules/governance/DeployRoleAuthorizer.s.sol";
import {DeployBancorVirtualSupplyBondingCurveFundingManager} from
    "script/modules/fundingManager/DeployBancorVirtualSupplyBondingCurveFundingManager.s.sol";
import {DeployTokenGatedRoleAuthorizer} from
    "script/modules/governance/DeployTokenGatedRoleAuthorizer.s.sol";
import {DeployStreamingPaymentProcessor} from
    "script/modules/paymentProcessor/DeployStreamingPaymentProcessor.s.sol";
import {DeployRecurringPaymentManager} from
    "script/modules/DeployRecurringPaymentManager.s.sol";
import {DeploySingleVoteGovernor} from
    "script/modules/DeploySingleVoteGovernor.s.sol";
import {DeployMetadataManager} from "script/utils/DeployMetadataManager.s.sol";

import {Ownable2Step} from "@oz/access/Ownable2Step.sol";

contract DeployTestnet is Script {
    error BeaconProxyDeploymentFailed();

    address governance = vm.envAddress("GOVERNANCE_CONTRACT_ADDRESS");
    address deployer = vm.envAddress("DEPLOYER_ADDRESS");

    // ------------------------------------------------------------------------
    // Instances of Deployer Scripts
    //Orchestrator
    DeployOrchestrator deployOrchestrator = new DeployOrchestrator();
    // Factories
    DeployModuleFactory deployModuleFactory = new DeployModuleFactory();
    TransferModuleFactoryOwnership transferModuleFactoryOwnership =
        new TransferModuleFactoryOwnership();
    DeployOrchestratorFactory deployOrchestratorFactory =
        new DeployOrchestratorFactory();
    // Funding Manager
    DeployRebasingFundingManager deployRebasingFundingManager =
        new DeployRebasingFundingManager();
    DeployBancorVirtualSupplyBondingCurveFundingManager
        deployBancorVirtualSupplyBondingCurveFundingManager =
            new DeployBancorVirtualSupplyBondingCurveFundingManager();
    // Authorizer
    DeployRoleAuthorizer deployRoleAuthorizer = new DeployRoleAuthorizer();
    DeployTokenGatedRoleAuthorizer deployTokenGatedRoleAuthorizer =
        new DeployTokenGatedRoleAuthorizer();
    // Payment Processor
    DeploySimplePaymentProcessor deploySimplePaymentProcessor =
        new DeploySimplePaymentProcessor();
    DeployStreamingPaymentProcessor deployStreamingPaymentProcessor =
        new DeployStreamingPaymentProcessor();
    // Logic Module
    DeployBountyManager deployBountyManager = new DeployBountyManager();
    DeployRecurringPaymentManager deployRecurringPaymentManager =
        new DeployRecurringPaymentManager();
    // Utils
    DeploySingleVoteGovernor deploySingleVoteGovernor =
        new DeploySingleVoteGovernor();
    DeployMetadataManager deployMetadataManager = new DeployMetadataManager();
    //Beacon
    DeployAndSetUpBeacon deployAndSetUpBeacon = new DeployAndSetUpBeacon();
    TransferBeaconOwnership transferBeaconOwnership =
        new TransferBeaconOwnership();
    // Transaction Forwarder
    DeployTransactionForwarder deployTransactionForwarder =
        new DeployTransactionForwarder();

    // ------------------------------------------------------------------------
    // Deployed Implementation Contracts

    //Orchestrator
    address orchestrator;

    //TransactionForwarder
    address forwarderImplementation;

    // Funding Manager
    address rebasingFundingManager;
    address bancorBondingCurveFundingManager;
    // Authorizer
    address roleAuthorizer;
    address tokenGatedRoleAuthorizer;
    // Payment Processor
    address simplePaymentProcessor;
    address streamingPaymentProcessor;
    // Logic Module
    address bountyManager;
    address recurringPaymentManager;
    // Utils
    address singleVoteGovernor;
    address metadataManager;

    // ------------------------------------------------------------------------
    // Beacons

    //TransactionForwarder
    address forwarderBeacon;
    // Funding Manager
    address rebasingFundingManagerBeacon;
    address bancorBondingCurveFundingManagerBeacon;
    // Authorizer
    address roleAuthorizerBeacon;
    address tokenGatedRoleAuthorizerBeacon;
    // Payment Processor
    address simplePaymentProcessorBeacon;
    address streamingPaymentProcessorBeacon;
    // Logic Module
    address bountyManagerBeacon;
    address recurringPaymentManagerBeacon;
    // Utils
    address singleVoteGovernorBeacon;
    address metadataManagerBeacon;

    // ------------------------------------------------------------------------
    // Deployed Proxy Contracts

    //These contracts will actually be used at the later point of time

    //TransactionForwarder
    address forwarder;

    // Factories
    address moduleFactory;
    address orchestratorFactory;

    // ------------------------------------------------------------------------
    // Module Metadata

    // ------------------------------------------------------------------------
    // Funding Manager

    IModule.Metadata rebasingFundingManagerMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "RebasingFundingManager"
    );

    IModule.Metadata bancorVirtualSupplyBondingCurveFundingManagerMetadata =
    IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "BancorVirtualSupplyBondingCurveFundingManager"
    );

    // ------------------------------------------------------------------------
    // Authorizer

    IModule.Metadata roleAuthorizerMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "RoleAuthorizer"
    );

    IModule.Metadata tokenGatedRoleAuthorizerMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "TokenGatedRoleAuthorizer"
    );

    // ------------------------------------------------------------------------
    // Payment Processor

    IModule.Metadata simplePaymentProcessorMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "SimplePaymentProcessor"
    );

    IModule.Metadata streamingPaymentProcessorMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "StreamingPaymentProcessor"
    );

    // ------------------------------------------------------------------------
    // Logic Module

    IModule.Metadata recurringPaymentManagerMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "RecurringPaymentManager"
    );

    IModule.Metadata bountyManagerMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "BountyManager"
    );

    // ------------------------------------------------------------------------
    // Utils

    IModule.Metadata singleVoteGovernorMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "SingleVoteGovernor"
    );

    IModule.Metadata metadataManagerMetadata = IModule.Metadata(
        1,
        0,
        "https://github.com/InverterNetwork/inverter-contracts",
        "MetadataManager"
    );

    /// @notice Deploys all necessary factories, beacons and implementations
    /// @return factory The addresses of the fully deployed orchestrator factory. All other addresses should be accessible from this.
    function run() public virtual returns (address factory) {
        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy forwarder implementation and proxy \n");
        //Deploy TransactionForwarder implementation
        forwarderImplementation = deployTransactionForwarder.run();

        //Deploy beacon and actual proxy
        (forwarderBeacon, forwarder) = deployAndSetUpBeacon
            .deployBeaconAndSetupProxy(forwarderImplementation, 1, 0);

        if (
            forwarder == forwarderImplementation || forwarder == forwarderBeacon
        ) {
            revert BeaconProxyDeploymentFailed();
        }

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy orchestrator implementation \n");
        //Orchestrator
        orchestrator = deployOrchestrator.run(forwarder);

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy factory implementations \n");

        //Deploy module Factory implementation
        moduleFactory = deployModuleFactory.run(forwarder);

        //Deploy orchestrator Factory implementation
        orchestratorFactory = deployOrchestratorFactory.run(
            orchestrator, moduleFactory, forwarder
        );

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy Modules Implementations \n");
        // Deploy implementation contracts.

        // Funding Manager
        rebasingFundingManager = deployRebasingFundingManager.run();
        bancorBondingCurveFundingManager =
            deployBancorVirtualSupplyBondingCurveFundingManager.run();
        // Authorizer
        roleAuthorizer = deployRoleAuthorizer.run();
        tokenGatedRoleAuthorizer = deployTokenGatedRoleAuthorizer.run();
        // Payment Processor
        simplePaymentProcessor = deploySimplePaymentProcessor.run();
        streamingPaymentProcessor = deployStreamingPaymentProcessor.run();
        // Logic Module
        bountyManager = deployBountyManager.run();
        recurringPaymentManager = deployRecurringPaymentManager.run();
        // Utils
        singleVoteGovernor = deploySingleVoteGovernor.run();
        metadataManager = deployMetadataManager.run();

        console2.log(
            "-----------------------------------------------------------------------------"
        );
        console2.log("Deploy module beacons and register in module factory \n");
        //Deploy Modules and Register in factories

        // Funding Manager
        rebasingFundingManagerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            rebasingFundingManager,
            moduleFactory,
            rebasingFundingManagerMetadata
        );
        bancorBondingCurveFundingManagerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            bancorBondingCurveFundingManager,
            moduleFactory,
            bancorVirtualSupplyBondingCurveFundingManagerMetadata
        );
        // Authorizer
        roleAuthorizerBeacon = deployAndSetUpBeacon.deployAndRegisterInFactory(
            roleAuthorizer, moduleFactory, roleAuthorizerMetadata
        );
        tokenGatedRoleAuthorizerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            tokenGatedRoleAuthorizer,
            moduleFactory,
            tokenGatedRoleAuthorizerMetadata
        );
        // Payment Processor
        simplePaymentProcessorBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            simplePaymentProcessor,
            moduleFactory,
            simplePaymentProcessorMetadata
        );
        streamingPaymentProcessorBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            streamingPaymentProcessor,
            moduleFactory,
            streamingPaymentProcessorMetadata
        );
        // Logic Module
        bountyManagerBeacon = deployAndSetUpBeacon.deployAndRegisterInFactory(
            bountyManager, moduleFactory, bountyManagerMetadata
        );
        recurringPaymentManagerBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            recurringPaymentManager,
            moduleFactory,
            recurringPaymentManagerMetadata
        );

        // Utils
        singleVoteGovernorBeacon = deployAndSetUpBeacon
            .deployAndRegisterInFactory(
            singleVoteGovernor, moduleFactory, singleVoteGovernorMetadata
        );
        metadataManagerBeacon = deployAndSetUpBeacon.deployAndRegisterInFactory(
            metadataManager, moduleFactory, metadataManagerMetadata
        );

        // Transfer of ownership of the contracts
        if (governance != deployer) {
            console2.log(
                "-----------------------------------------------------------------------------"
            );
            console2.log("Transferring the ownership of all contracts\n");

            // Beacons
            transferBeaconOwnership.run(
                rebasingFundingManagerBeacon, governance
            );
            transferBeaconOwnership.run(
                bancorBondingCurveFundingManagerBeacon, governance
            );
            transferBeaconOwnership.run(roleAuthorizerBeacon, governance);
            transferBeaconOwnership.run(
                tokenGatedRoleAuthorizerBeacon, governance
            );
            transferBeaconOwnership.run(
                simplePaymentProcessorBeacon, governance
            );
            transferBeaconOwnership.run(
                streamingPaymentProcessorBeacon, governance
            );
            transferBeaconOwnership.run(bountyManagerBeacon, governance);
            transferBeaconOwnership.run(
                recurringPaymentManagerBeacon, governance
            );
            transferBeaconOwnership.run(singleVoteGovernorBeacon, governance);
            transferBeaconOwnership.run(metadataManagerBeacon, governance);

            // Factories
            transferModuleFactoryOwnership.run(moduleFactory, governance);
        }

        // Transfer Factory Auth TODO
        return (orchestratorFactory);
    }
}