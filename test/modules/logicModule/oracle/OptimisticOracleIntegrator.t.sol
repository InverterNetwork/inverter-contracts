// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// SuT
import {OptimisticOracleIntegratorMock} from
    "test/modules/logicModule/oracle/utils/OptimisiticOracleIntegratorMock.sol";

import {OptimisticOracleV3Mock} from
    "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    OptimisticOracleIntegrator,
    IOptimisticOracleIntegrator
} from
    "@lm/abstracts/oracleIntegrations/UMA_OptimisticOracleV3/OptimisticOracleIntegrator.sol";

contract OptimisticOracleIntegratorTest is ModuleTest {
    address ooIntegratorImplementation;
    OptimisticOracleIntegratorMock ooIntegrator;
    OptimisticOracleV3Mock ooV3;

    uint64 immutable DEFAULT_LIVENESS = 5000;

    // Mock data for assertions
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x0);

    // Setup + Init

    function setUp() public {
        ooV3 = new OptimisticOracleV3Mock(_token, DEFAULT_LIVENESS);
        // we whitelist the default currency
        ooV3.whitelistCurrency(address(_token), 5e17);

        //Add Module to Mock Orchestrator
        ooIntegratorImplementation =
            address(new OptimisticOracleIntegratorMock());
        ooIntegrator = OptimisticOracleIntegratorMock(
            Clones.clone(ooIntegratorImplementation)
        );

        _setUpOrchestrator(ooIntegrator);

        _authorizer.setAllAuthorized(true);

        assertEq(address(_authorizer), address(_orchestrator.authorizer()));

        //console.log("Token address: ", address(_token));
        //console.log("Optimistic Oracle address: ",address(ooV3));
        bytes memory _configData =
            abi.encode(address(_token), address(ooV3), DEFAULT_LIVENESS);
        //console.log("Optimistic Oracle config data (next line): ");
        //console.logBytes(_configData);

        ooIntegrator.init(_orchestrator, _METADATA, _configData);
        _token.mint(address(this), 1e22);
        _token.approve(address(ooIntegrator), 1e22);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        //set up new orchestrator
        ooIntegratorImplementation =
            address(new OptimisticOracleIntegratorMock());
        ooIntegrator = OptimisticOracleIntegratorMock(
            Clones.clone(ooIntegratorImplementation)
        );
        _setUpOrchestrator(ooIntegrator);

        bytes memory _configData =
            abi.encode(address(_token), address(ooV3), DEFAULT_LIVENESS);

        //Init Module wrongly
        vm.expectRevert(IModule_v1.Module__InvalidOrchestratorAddress.selector);
        ooIntegrator.init(IOrchestrator_v1(address(0)), _METADATA, _configData);

        // Test invalid token
        vm.expectRevert();
        ooIntegrator.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(0), address(ooV3), DEFAULT_LIVENESS)
        );

        // Test invalid OOAddress. See comment in OOIntegrator contract
        vm.expectRevert();
        ooIntegrator.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(_token), address(0), DEFAULT_LIVENESS)
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        ooIntegrator.init(_orchestrator, _METADATA, bytes(""));
    }

    // Tests

    /*
        Gets the stored data
            When the assertion is not resolved
                 returns false and 0
            When the assertion is resolved
                 returns true + the correct data


    */
    function testGetData_ReturnsZeroWhenAssertionNotResolved() public {
        bytes32 assertionId = createMockAssertion(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS
        );

        (bool assertionResolved, bytes32 data) =
            ooIntegrator.getData(assertionId);

        assertEq(assertionResolved, false);
        assertEq(data, 0);
    }

    function testGetData() public {
        bytes32 assertionId = createMockAssertion(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS
        );

        resolveMockAssertion(assertionId);

        (bool assertionResolved, bytes32 data) =
            ooIntegrator.getData(assertionId);

        assertEq(assertionResolved, true);
        assertEq(data, MOCK_ASSERTION_DATA);
    }

    //==========================================================================
    // Setter Functions

    /*
        When the caller is not the owner
            reverts (tested in module tests)
        When the caller is the owner
            when the address is 0
                reverts
            when the address is a valid token
                sets the new address as default currency
                emits an event
        
        // Note: checks if the token is whitelisted in the OptimisticOracleV3 are performed when creating an assertion, not when setting the default currency

    */

    function testSetDefaultCurrencyFails_whenNewCurrencyIsZero() public {
        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__InvalidDefaultCurrency
                .selector
        );
        ooIntegrator.setDefaultCurrency(address(0));
    }

    function testSetDefaultCurrency(address whitelisted) public {
        _validateAddress(whitelisted); // make sure it doesn't collide with addresses in use by the test

        ooV3.whitelistCurrency(whitelisted, 0);

        ooIntegrator.setDefaultCurrency(whitelisted);

        assertEq(address(ooIntegrator.defaultCurrency()), whitelisted);
    }

    /*
        When the caller is not the owner
            reverts (tested in module tests)
        When the caller is the owner
            when the address is 0
                reverts
            when the address is not an UMA OO instance 
                reverts
            when the address is valid 
                sets the new address as optimistic oracle
                emits an event
    */
    function testSetOptimisticOracleFails_WhenNewOracleIsZero() public {
        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__InvalidOOInstance
                .selector
        );
        ooIntegrator.setOptimisticOracle(address(0));
    }

    /*
    function testSetOptimisticOracleFails_WhenNewOracleIsNotUmaOptimisticOracle(
        address notOracle
    ) public {
        _validateAddress(notOracle);
        vm.expectRevert();
        ooIntegrator.setOptimisticOracle(notOracle);
    }
    */

    function testSetOptimisticOracle() public {
        OptimisticOracleV3Mock newOracle =
            new OptimisticOracleV3Mock(_token, DEFAULT_LIVENESS);
        ooIntegrator.setOptimisticOracle(address(newOracle));
        assertEq(address(ooIntegrator.oo()), address(newOracle));
    }

    /*
        When the caller is not the owner
            reverts (tested in module tests)
        When the caller is the owner
            when the liveness is 0
                reverts
            when the liveness is valid 
                sets the new liveness
                emits an event
    */

    function testSetDefaultAssertionLivenessFails_whenLivenessIsZero() public {
        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__InvalidDefaultLiveness
                .selector
        );
        ooIntegrator.setDefaultAssertionLiveness(0);
    }

    function testSetDefaultAssertionLiveness(uint64 newLiveness) public {
        vm.assume(newLiveness > 0);
        ooIntegrator.setDefaultAssertionLiveness(newLiveness);
        assertEq(ooIntegrator.assertionLiveness(), newLiveness);
    }

    /*
        When the caller does not have asserter role
            reverts 
        when the caller has the asserter role
            when the asserter address is 0
                it uses msgSender as asserter address
                    when the caller does not have enough funds for the bond
                        reverts
                    when the caller has enough funds for the bond
                        the contract takes the funds for the bond
                        the OO receives the bond
                        the assertion gets stored with a unique id
                        emits an event
            when the asserter address is not 0
                    when the caller does not have enough funds for the bond
                        reverts
                    when the caller has enough funds for the bond
                        the contract takes the funds for the bond
                        the OO receives the bond
                        the assertion gets stored with a unique id
                        emits an event


    */
    //Maybe better here?
    function testAssertDataFor_whenCallerDoesNotHaveAsserterRole(address who)
        public
    {
        bytes32 roleId = _authorizer.generateRoleId(
            address(ooIntegrator), ooIntegrator.ASSERTER_ROLE()
        );
        _authorizer.setAllAuthorized(false);
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector,
                roleId,
                address(0xBEEF)
            )
        );
        ooIntegrator.assertDataFor(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS
        );
    }

    function testAssertDataFor_whenAsserterAddressIsZero() public {
        address prankUser = address(0x987654321);
        _token.mint(prankUser, 1e18);
        vm.prank(prankUser);
        _token.approve(address(ooIntegrator), 1e20);
        //get user balance before
        uint userBalanceBefore = _token.balanceOf(prankUser);
        // get OO balance before
        uint ooBalanceBefore = _token.balanceOf(address(ooV3));

        //Since we are using the mockauthorizer, the asserter has the asserter role
        vm.prank(prankUser);
        ooIntegrator.assertDataFor(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, address(0)
        );

        //assert user balance has been reduced by $bond
        assertEq(_token.balanceOf(prankUser), userBalanceBefore - 1e18);
        //assert OO balance has ben increased by $bond
        assertEq(_token.balanceOf(address(ooV3)), ooBalanceBefore + 1e18);
    }

    function testAssertDataForFails_whenCallerDoesNotHaveEnoughFundsForBond()
        public
    {
        address prankUser = address(0x987654321);
        _token.mint(prankUser, 1e9);
        vm.prank(prankUser);
        _token.approve(address(ooIntegrator), 1e20);
        //get user balance before
        uint userBalanceBefore = _token.balanceOf(prankUser);
        // get OO balance before
        uint ooBalanceBefore = _token.balanceOf(address(ooV3));

        //Since we are using the mockauthorizer, the asserter has the asserter role
        vm.prank(prankUser);
        vm.expectRevert();
        ooIntegrator.assertDataFor(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, prankUser
        );

        //assert user balance has been reduced by $bond
        assertEq(_token.balanceOf(prankUser), userBalanceBefore);
        //assert OO balance has ben increased by $bond
        assertEq(_token.balanceOf(address(ooV3)), ooBalanceBefore);
    }

    function testAssertDataFor_whenAsserterAddressIsNotZero() public {
        address prankUser = address(0x987654321);
        _token.mint(prankUser, 1e18);
        vm.prank(prankUser);
        _token.approve(address(ooIntegrator), 1e20);
        //get user balance before
        uint userBalanceBefore = _token.balanceOf(prankUser);
        // get OO balance before
        uint ooBalanceBefore = _token.balanceOf(address(ooV3));

        //Since we are using the mockauthorizer, the asserter has the asserter role
        vm.prank(prankUser);
        ooIntegrator.assertDataFor(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, prankUser
        );

        //assert user balance has been reduced by $bond
        assertEq(_token.balanceOf(prankUser), userBalanceBefore - 1e18);
        //assert OO balance has ben increased by $bond
        assertEq(_token.balanceOf(address(ooV3)), ooBalanceBefore + 1e18);
    }

    /*
        When the caller is not the OO
            it reverts
        When the caller is the OO
            If the assertion was deemed false
                deletes the assertionData linked to that assertionID
            If the assertion was deemed true
                the 'resolved' state in storage changes to true 
                emits an event
    */

    function testAssertioResolvedCallbackFails_whenCallerNotTheOO() public {
        bytes32 assertionId = createMockAssertion(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOptimisticOracleIntegrator
                    .Module__OptimisticOracleIntegrator__CallerNotOO
                    .selector
            )
        );
        ooIntegrator.assertionResolvedCallback(assertionId, true);
    }

    function testAssertioResolvedCallback_whenResolvedTrue() public {
        bytes32 assertionId = createMockAssertion(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS
        );
        vm.prank(address(ooV3));
        ooIntegrator.assertionResolvedCallback(assertionId, true);

        (bool assertionResolved, bytes32 data) =
            ooIntegrator.getData(assertionId);

        assertEq(assertionResolved, true);
        assertEq(data, MOCK_ASSERTION_DATA);
    }

    function testAssertioResolvedCallback_whenResolvedFalse() public {
        bytes32 assertionId = createMockAssertion(
            MOCK_ASSERTION_DATA_ID, MOCK_ASSERTION_DATA, MOCK_ASSERTER_ADDRESS
        );

        vm.prank(address(ooV3));
        ooIntegrator.assertionResolvedCallback(assertionId, false);

        (bool assertionResolved, bytes32 data) =
            ooIntegrator.getData(assertionId);

        assertEq(assertionResolved, false);
        assertEq(data, bytes32(0));
    }

    /*
     Nothing happens (maybe necessary to mock for coverage? )
     */
    function assertionDisputedCallback(bytes32 assertionId) public virtual {}

    // Helper Functions

    function createMockAssertion(bytes32 dataId, bytes32 data, address asserter)
        internal
        returns (bytes32 assertionId)
    {
        assertionId = ooIntegrator.assertDataFor(dataId, data, asserter);
    }

    function resolveMockAssertion(bytes32 assertionId)
        internal
        returns (bool assertionResult)
    {
        vm.warp(block.timestamp + DEFAULT_LIVENESS + 1);
        assertionResult = ooV3.settleAndGetAssertionResult(assertionId);

        // The callback gets called in the above statement
    }
    // make sure an address doesn't collide with addresses in use by the test

    function _validateAddress(address validate) internal view {
        // Checks for:
        // address 0
        vm.assume(validate != address(0));
        // OO
        vm.assume(validate != address(ooV3));
        // Integrator
        vm.assume(validate != address(ooIntegrator));
        // Integrator Implementation
        vm.assume(validate != ooIntegratorImplementation);
        // this
        vm.assume(validate != address(this));
    }
}
