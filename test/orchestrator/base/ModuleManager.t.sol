// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

// SuT
import {
    ModuleManagerMock,
    IModuleManager
} from "test/utils/mocks/orchestrator/base/ModuleManagerMock.sol";

// Mocks
import {AuthorizerMock} from "test/utils/mocks/modules/AuthorizerMock.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// Helper
import {TypeSanityHelper} from "test/orchestrator/helper/TypeSanityHelper.sol";

contract ModuleManagerTest is Test {
    // SuT
    ModuleManagerMock moduleManager;

    // Helper
    TypeSanityHelper types;

    // Constants
    uint MAX_MODULES = 128;
    address[] EMPTY_LIST = new address[](0);

    // Events copied from SuT.
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    event ModuleRoleGranted(
        address indexed module, bytes32 indexed role, address indexed account
    );
    event ModuleRoleRevoked(
        address indexed module, bytes32 indexed role, address indexed account
    );

    function setUp() public {
        moduleManager = new ModuleManagerMock(address(0));
        moduleManager.init(EMPTY_LIST);

        types = new TypeSanityHelper(address(moduleManager));

        moduleManager.__ModuleManager_setIsAuthorized(address(this), true);
    }

    //--------------------------------------------------------------------------
    // Tests: Initialization

    function testInit(address[] memory modules) public {
        moduleManager = new ModuleManagerMock(address(0));
        types = new TypeSanityHelper(address(moduleManager));

        types.assumeValidModules(modules);

        if (modules.length > (MAX_MODULES - 3)) {
            vm.expectRevert(
                IModuleManager
                    .Orchestrator__ModuleManager__ModuleAmountOverLimits
                    .selector
            );

            moduleManager.init(modules);
        } else {
            moduleManager.init(modules);

            // List of modules should be size of modules array.
            address[] memory modulesAdded = moduleManager.listModules();
            assertEq(modulesAdded.length, modules.length);

            // Each module should be added.
            for (uint i; i < modules.length; ++i) {
                assertTrue(moduleManager.isModule(modules[i]));
            }
        }
    }

    function testReinitFails() public {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        moduleManager.init(EMPTY_LIST);
    }

    function testInitFailsForNonInitializerFunction() public {
        vm.expectRevert(OZErrors.Initializable__NotInitializing);
        moduleManager.initNoInitializer(EMPTY_LIST);
    }

    function testInitFailsForInvalidModules() public {
        moduleManager = new ModuleManagerMock(address(0));
        types = new TypeSanityHelper(address(moduleManager));

        address[] memory invalids = types.createInvalidModules();

        address[] memory modules = new address[](1);

        for (uint i; i < invalids.length; ++i) {
            modules[0] = invalids[i];

            vm.expectRevert(
                IModuleManager
                    .Orchestrator__ModuleManager__InvalidModuleAddress
                    .selector
            );
            moduleManager.init(modules);
        }
    }

    function testInitFailsIfModuleAddedTwice() public {
        moduleManager = new ModuleManagerMock(address(0));
        types = new TypeSanityHelper(address(moduleManager));

        address[] memory modules = new address[](2);
        modules[0] = address(0xCAFE);
        modules[1] = address(0xCAFE);

        vm.expectRevert(
            IModuleManager.Orchestrator__ModuleManager__IsModule.selector
        );
        moduleManager.init(modules);
    }

    function testInitFailsForTooManyModules(address[] memory modules) public {
        vm.assume(modules.length > MAX_MODULES);

        //we don't need to check for validity since it should revert before

        moduleManager = new ModuleManagerMock(address(0));
        vm.expectRevert(
            IModuleManager
                .Orchestrator__ModuleManager__ModuleAmountOverLimits
                .selector
        );
        moduleManager.init(modules);
    }

    //--------------------------------------------------------------------------
    // Tests: Public View Functions

    //--------------------------------------------------------------------------
    // Tests: Transaction Execution

    function testExecuteTxFromModuleOnlyCallableByModule() public {
        vm.expectRevert(
            IModuleManager
                .Orchestrator__ModuleManager__OnlyCallableByModule
                .selector
        );
        moduleManager.executeTxFromModule(address(this), bytes(""));
    }

    function testExecuteTxFromModuleViaCall() public {
        address module = address(0xCAFE);
        moduleManager.addModule(module);

        bool ok_;
        bytes memory returnData;

        vm.prank(module);
        (ok_, returnData) = moduleManager.executeTxFromModule(
            address(this), abi.encodeWithSignature("ok()")
        );

        assertTrue(ok_);
        assertTrue(abi.decode(returnData, (bool)));
    }

    function testExecuteTxFromModuleViaCallFails() public {
        address module = address(0xCAFE);
        moduleManager.addModule(module);

        bool ok_;
        bytes memory returnData;

        vm.prank(module);
        (ok_, returnData) = moduleManager.executeTxFromModule(
            address(this), abi.encodeWithSignature("fails()")
        );

        assertTrue(!ok_);
    }

    function ok() public pure returns (bool) {
        return true;
    }

    function fails() public pure {
        revert("failed");
    }

    //--------------------------------------------------------------------------
    // Tests: Module Management

    //----------------------------------
    // Tests: addModules()

    function testAddModule(address[] memory whos) public {
        vm.assume(whos.length <= MAX_MODULES);
        types.assumeValidModules(whos);

        for (uint i; i < whos.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit ModuleAdded(whos[i]);

            moduleManager.addModule(whos[i]);

            assertTrue(moduleManager.isModule(whos[i]));
        }

        // Note that list is traversed.
        address[] memory modules = moduleManager.listModules();

        assertEq(modules.length, whos.length);
        for (uint i; i < whos.length; ++i) {
            assertEq(modules[i], whos[i]);
        }
    }

    function testAddModuleFailsIfCallerNotAuthorized(address who) public {
        types.assumeValidModule(who);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManager
                .Orchestrator__ModuleManager__CallerNotAuthorized
                .selector
        );
        moduleManager.addModule(who);
    }

    function testAddModuleFailsIfAlreadyAdded(address who) public {
        types.assumeValidModule(who);

        moduleManager.addModule(who);

        vm.expectRevert(
            IModuleManager.Orchestrator__ModuleManager__IsModule.selector
        );
        moduleManager.addModule(who);
    }

    function testAddModuleFailsForInvalidAddress() public {
        address[] memory invalids = types.createInvalidModules();

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IModuleManager
                    .Orchestrator__ModuleManager__InvalidModuleAddress
                    .selector
            );
            moduleManager.addModule(invalids[i]);
        }
    }

    function testAddModuleFailsIfLimitReached(address[] calldata whos) public {
        vm.assume(whos.length > MAX_MODULES);
        types.assumeValidModules(whos[:MAX_MODULES]);

        for (uint i; i < MAX_MODULES; ++i) {
            vm.expectEmit(true, true, true, true);
            emit ModuleAdded(whos[i]);

            moduleManager.addModule(whos[i]);

            assertTrue(moduleManager.isModule(whos[i]));
        }

        vm.expectRevert(
            IModuleManager
                .Orchestrator__ModuleManager__ModuleAmountOverLimits
                .selector
        );
        moduleManager.addModule(whos[MAX_MODULES]);
    }

    //----------------------------------
    // Tests: removeModules()

    function testRemoveModules(address[] memory whos) public {
        vm.assume(whos.length != 0);
        vm.assume(whos.length <= MAX_MODULES);
        types.assumeValidModules(whos);

        // The current module to remove.
        address module;

        // Add modules.
        for (uint i; i < whos.length; ++i) {
            moduleManager.addModule(whos[i]);
        }

        // Remove modules from the front until list is empty.
        for (uint i; i < whos.length; ++i) {
            module = whos[whos.length - i - 1];

            vm.expectEmit(true, true, true, true);
            emit ModuleRemoved(module);

            moduleManager.removeModule(module);

            assertTrue(!moduleManager.isModule(module));
        }
        assertEq(moduleManager.listModules().length, 0);

        // Add modules again.
        for (uint i; i < whos.length; ++i) {
            moduleManager.addModule(whos[i]);
        }

        // Remove modules from the back until list is empty.

        for (uint i; i < whos.length; ++i) {
            module = whos[i];

            vm.expectEmit(true, true, true, true);
            emit ModuleRemoved(module);

            moduleManager.removeModule(module);

            assertTrue(!moduleManager.isModule(module));
        }

        assertEq(moduleManager.listModules().length, 0);
    }

    function testRemoveModuleFailsIfCallerNotAuthorized(address who) public {
        types.assumeValidModule(who);

        moduleManager.addModule(who);

        moduleManager.__ModuleManager_setIsAuthorized(address(this), false);

        vm.expectRevert(
            IModuleManager
                .Orchestrator__ModuleManager__CallerNotAuthorized
                .selector
        );
        moduleManager.removeModule(who);
    }

    function testRemoveModuleFailsIfNotModule(address who) public {
        types.assumeValidModule(who);

        vm.expectRevert(
            IModuleManager.Orchestrator__ModuleManager__IsNotModule.selector
        );
        moduleManager.removeModule(who);
    }
}
