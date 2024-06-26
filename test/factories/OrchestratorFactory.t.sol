// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Dependencies
import {OrchestratorFactory} from "src/factories/OrchestratorFactory.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// Internal Interfaces
import {
    IOrchestratorFactory,
    IModule,
    IOrchestrator
} from "src/factories/IOrchestratorFactory.sol";

import {Orchestrator} from "src/orchestrator/Orchestrator.sol";

// Mocks
import {ModuleFactoryMock} from
    "test/utils/mocks/factories/ModuleFactoryMock.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

contract OrchestratorFactoryTest is Test {
    bool hasDependency;
    string[] dependencies = new string[](0);

    // SuT
    OrchestratorFactory factory;

    Orchestrator target;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new orchestrator is created.
    /// @param orchestratorId The id of the orchestrator.
    /// @param orchestratorAddress The address of the orchestrator.
    event OrchestratorCreated(
        uint indexed orchestratorId, address indexed orchestratorAddress
    );

    // Mocks
    ModuleFactoryMock moduleFactory;

    // Metadata
    IOrchestratorFactory.OrchestratorConfig orchestratorConfig =
    IOrchestratorFactory.OrchestratorConfig({
        owner: address(this),
        token: IERC20(new ERC20Mock("Mock Token", "MOCK"))
    });

    IOrchestratorFactory.ModuleConfig fundingManagerConfig =
    IOrchestratorFactory.ModuleConfig(
        IModule.Metadata(1, 1, "https://fundingmanager.com", "FundingManager"),
        bytes("data"),
        abi.encode(hasDependency, dependencies)
    );

    IOrchestratorFactory.ModuleConfig authorizerConfig = IOrchestratorFactory
        .ModuleConfig(
        IModule.Metadata(1, 1, "https://authorizer.com", "Authorizer"),
        abi.encode(address(this), address(this)),
        abi.encode(hasDependency, dependencies)
    );

    IOrchestratorFactory.ModuleConfig paymentProcessorConfig =
    IOrchestratorFactory.ModuleConfig(
        IModule.Metadata(
            1, 1, "https://paymentprocessor.com", "SimplePaymentProcessor"
        ),
        bytes("data"),
        abi.encode(hasDependency, dependencies)
    );

    IOrchestratorFactory.ModuleConfig moduleConfig = IOrchestratorFactory
        .ModuleConfig(
        IModule.Metadata(1, 1, "https://module.com", "Module"),
        bytes(""),
        abi.encode(hasDependency, dependencies)
    );

    function setUp() public {
        moduleFactory = new ModuleFactoryMock();

        target = new Orchestrator(address(0));

        factory = new OrchestratorFactory(
            address(target), address(moduleFactory), address(0)
        );
    }

    function testValidOrchestratorId(uint getId, uint orchestratorsCreated)
        public
    {
        // Note to stay reasonable
        orchestratorsCreated = bound(orchestratorsCreated, 0, 50);

        for (uint i = 0; i < orchestratorsCreated; ++i) {
            _deployOrchestrator();
        }

        if (getId > orchestratorsCreated) {
            vm.expectRevert(
                IOrchestratorFactory.OrchestratorFactory__InvalidId.selector
            );
        }
        factory.getOrchestratorByID(getId);
    }

    function testDeploymentInvariants() public {
        assertEq(factory.target(), address(target));
        assertEq(factory.moduleFactory(), address(moduleFactory));
    }

    function testCreateOrchestrator(uint modulesLen) public {
        // Note to stay reasonable
        modulesLen = bound(modulesLen, 0, 50);

        // Create optional ModuleConfig instances.
        IOrchestratorFactory.ModuleConfig[] memory moduleConfigs =
            new IOrchestratorFactory.ModuleConfig[](modulesLen);
        for (uint i; i < modulesLen; ++i) {
            moduleConfigs[i] = moduleConfig;
        }

        vm.expectEmit(true, false, false, false);
        emit OrchestratorCreated(1, address(0)); // Since we don't know the address of the orchestrator

        // Deploy Orchestrator with id=1
        IOrchestrator orchestrator = factory.createOrchestrator(
            orchestratorConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        // Check that orchestrator's strorage correctly initialized.
        assertEq(orchestrator.orchestratorId(), 1);
        assertTrue(address(orchestrator.authorizer()) != address(0));
        assertTrue(address(orchestrator.paymentProcessor()) != address(0));

        vm.expectEmit(true, false, false, false);
        emit OrchestratorCreated(2, address(0)); //since we don't know the address of the orchestrator

        // Deploy Orchestrator with id=2
        orchestrator = factory.createOrchestrator(
            orchestratorConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );
        // Only check that orchestrator's id is correct.
        assertEq(orchestrator.orchestratorId(), 2);

        //check that orchestratorFactory idCounter is correct.
        assertEq(factory.getOrchestratorIDCounter(), 2);
    }

    function testOrchestratorMapping(uint orchestratorAmount) public {
        // Note to stay reasonable
        orchestratorAmount = bound(orchestratorAmount, 0, 50);

        for (uint i = 1; i < orchestratorAmount; ++i) {
            address orchestrator = _deployOrchestrator();
            assertEq(orchestrator, factory.getOrchestratorByID(i));
        }
    }

    function _deployOrchestrator() private returns (address) {
        //Create Empty ModuleConfig
        IOrchestratorFactory.ModuleConfig[] memory moduleConfigs =
            new IOrchestratorFactory.ModuleConfig[](0);

        vm.expectEmit(false, false, false, false);
        emit OrchestratorCreated(0, address(0)); // Since we don't know the id/address of the orchestrator

        // Deploy Orchestrator
        IOrchestrator orchestrator = factory.createOrchestrator(
            orchestratorConfig,
            fundingManagerConfig,
            authorizerConfig,
            paymentProcessorConfig,
            moduleConfigs
        );

        return address(orchestrator);
    }
}
