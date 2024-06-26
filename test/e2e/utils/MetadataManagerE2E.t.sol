// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {RoleAuthorizer} from "src/modules/authorizer/RoleAuthorizer.sol";

//Internal Dependencies
import {
    E2ETest, IOrchestratorFactory, IOrchestrator
} from "test/e2e/E2ETest.sol";

import {
    IMetadataManager,
    MetadataManager
} from "src/modules/utils/MetadataManager.sol";

contract MetadataManagerE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory.ModuleConfig[] moduleConfigurations;

    // E2E Test Variables

    function setUp() public override {
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // FundingManager
        setUpRebasingFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                rebasingFundingManagerMetadata,
                abi.encode(address(token)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // Authorizer
        setUpTokenGatedRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                tokenRoleAuthorizerMetadata,
                abi.encode(address(this), address(this)),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                simplePaymentProcessorMetadata,
                bytes(""),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );

        // MetadataManager
        // !!! Note !!!
        // In contrary to most other modules most of the purpose of the MetadataManeger can already be fulfilled during its creation.
        // As the purpose of the Metadatamanager is to provide users of the orchestrator with information about it.
        // This can already be done during initialization:

        //ManagerMetadata contains data about the manager of the orchestrator
        IMetadataManager.ManagerMetadata memory MANAGER_METADATA =
        // Name, Address, Twitter Handle
        IMetadataManager.ManagerMetadata("John Doe", address(0xBEEF), "@JonDoe");

        //OrchestratorMetadata contains data about the orchestrator itself
        IMetadataManager.OrchestratorMetadata memory ORCHESTRATOR_METADATA =
        IMetadataManager.OrchestratorMetadata(
            //Title of the project
            "Inverter Project",
            //Short description
            "This is a palceholder of a short description",
            //Long description
            "This is a palceholder of a long description",
            new string[](2), //This contains the external Media Data. Put in anything you see fit here
            new string[](3) //This contains categories that the orchestrator project could be put into. This should ideally make it easier for users to find what they are looking for.
        );

        ORCHESTRATOR_METADATA.externalMedias[0] = "Discord: https://...";
        ORCHESTRATOR_METADATA.externalMedias[1] = "Instagram: https://.....";

        ORCHESTRATOR_METADATA.categories[0] = "Community Building";
        ORCHESTRATOR_METADATA.categories[1] = "Token Workflows";
        ORCHESTRATOR_METADATA.categories[2] = "Modularity";

        //TeamMetadata contains data about the people behind the project
        //Its an array of MemberMetadata so multiple members can be put in here
        IMetadataManager.MemberMetadata[] memory TEAM_METADATA =
            new IMetadataManager.MemberMetadata[](2);

        TEAM_METADATA[0] = IMetadataManager.MemberMetadata(
            // Name, Address, Twitter Handle
            "Jane Doe",
            address(0xADA),
            "@JaneDoe"
        );
        TEAM_METADATA[1] = IMetadataManager.MemberMetadata(
            "Max Mustermann", address(0xB0B), "@MaxMustermann"
        );

        setUpMetadataManager();
        moduleConfigurations.push(
            IOrchestratorFactory.ModuleConfig(
                metadataManagerMetadata,
                //encode the wanted metadata in the initilization step
                abi.encode(
                    MANAGER_METADATA, ORCHESTRATOR_METADATA, TEAM_METADATA
                ),
                abi.encode(HAS_NO_DEPENDENCIES, EMPTY_DEPENDENCY_LIST)
            )
        );
    }

    function test_e2e_MetadataManager() public {
        //--------------------------------------------------------------------------------
        // Orchestrator Initialization
        //--------------------------------------------------------------------------------

        IOrchestratorFactory.OrchestratorConfig memory orchestratorConfig =
        IOrchestratorFactory.OrchestratorConfig({
            owner: address(this),
            token: token
        });

        IOrchestrator orchestrator =
            _create_E2E_Orchestrator(orchestratorConfig, moduleConfigurations);

        //--------------------------------------------------------------------------------
        // Module E2E Test
        //--------------------------------------------------------------------------------

        // Find MetadataManager
        IMetadataManager metadataManager;

        //Get all Modules
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            //Find the one that can fulfill the IMetadataFunction
            try IMetadataManager(modulesList[i]).getManagerMetadata() returns (
                IMetadataManager.ManagerMetadata memory
            ) {
                metadataManager = MetadataManager(modulesList[i]);
                break;
            } catch {
                continue;
            }
        }

        // Lets assume a user wants to look into the metadata
        // They will query it
        // Lets fetch the Name of the manager
        assertEq(metadataManager.getManagerMetadata().name, "John Doe");

        // Or the title of the Project
        assertEq(
            metadataManager.getOrchestratorMetadata().title, "Inverter Project"
        );

        // In case there is a change in the project behind the scenes we want to adapt the metadata accordingly
        // For example another person joined the team

        // First we need to adapt the TeamMetadata
        IMetadataManager.MemberMetadata[] memory TEAM_METADATA =
            new IMetadataManager.MemberMetadata[](3);

        TEAM_METADATA[0] = IMetadataManager.MemberMetadata(
            "Jane Doe", address(0xADA), "@JaneDoe"
        );
        TEAM_METADATA[1] = IMetadataManager.MemberMetadata(
            "Max Mustermann", address(0xB0B), "@MaxMustermann"
        );
        TEAM_METADATA[2] =
        // this person is newly added
        IMetadataManager.MemberMetadata(
            "Castellan Crowe", address(0x666), "@CastellanCrowe"
        );

        metadataManager.setTeamMetadata(TEAM_METADATA);

        // Lets see if it worked
        // The name of the third person should be the same as the one we set
        assertEq(metadataManager.getTeamMetadata()[2].name, "Castellan Crowe");
    }
}
