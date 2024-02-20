// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// External Libraries
import {Clones} from "@oz/proxy/Clones.sol";

//Internal Dependencies
import {ModuleTest, IModule, IOrchestrator} from "test/modules/ModuleTest.sol";

// Errors
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// SuT
import {
    KPIRewarder,
    IKPIRewarder,
    IOptimisticOracleIntegrator,
    IStakingManager,
    IERC20PaymentClient
} from "src/modules/logicModule/KPIRewarder.sol";

import {
    OptimisticOracleV3Mock,
    OptimisticOracleV3Interface
} from "test/modules/logicModule/oracle/utils/OptimisiticOracleV3Mock.sol";

import {StakingManagerAccessMock} from
    "test/utils/mocks/modules/logicModules/StakingManagerAccessMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract KPIRewarderTest is ModuleTest {
    // SuT
    KPIRewarder kpiManager;

    OptimisticOracleV3Mock ooV3;

    uint64 immutable DEFAULT_LIVENESS = 5000;

    // Mock data for assertions
    bytes32 constant MOCK_ASSERTION_DATA_ID = "0x1234";
    bytes32 constant MOCK_ASSERTION_DATA = "This is test data";
    address constant MOCK_ASSERTER_ADDRESS = address(0x1);
    address USER_1 = address(0xA1BA);

    ERC20Mock stakingToken = new ERC20Mock("Staking Mock Token", "STAKE MOCK");
    ERC20Mock rewardToken =
        new ERC20Mock("KPI Reward Mock Token", "REWARD MOCK");
    ERC20Mock feeToken = new ERC20Mock("OOV3 Fee Mock Token", "FEE MOCK");

    // Events
    event Staked(address indexed user, uint amount);
    event DataAsserted(
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );
    event DataAssertionResolved(
        bool assertedTruthfully,
        bytes32 indexed dataId,
        bytes32 data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    function setUp() public {
        ooV3 = new OptimisticOracleV3Mock(feeToken, DEFAULT_LIVENESS);
        // we whitelist the default currency
        ooV3.whitelistCurrency(address(feeToken), 5e17);

        //Add Module to Mock Orchestrator
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        _authorizer.setIsAuthorized(address(this), true);

        bytes memory configData =
            abi.encode(address(stakingToken), address(feeToken), ooV3);

        kpiManager.init(_orchestrator, _METADATA, configData);
    }

    //--------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        address impl = address(new KPIRewarder());
        kpiManager = KPIRewarder(Clones.clone(impl));

        _setUpOrchestrator(kpiManager);

        bytes memory configData =
            abi.encode(address(stakingToken), address(rewardToken), ooV3);

        //Init Module wrongly
        vm.expectRevert(IModule.Module__InvalidOrchestratorAddress.selector);
        kpiManager.init(IOrchestrator(address(0)), _METADATA, configData);

        // Test invalid staking token
        vm.expectRevert(
            IStakingManager.Module__StakingManager__InvalidStakingToken.selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(0), address(rewardToken), address(ooV3))
        );

        // Test invalid reward token
        vm.expectRevert(
            IOptimisticOracleIntegrator
                .Module__OptimisticOracleIntegrator__InvalidDefaultCurrency
                .selector
        );
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(stakingToken), address(0), address(ooV3))
        );

        // Test invalid OOAddress. See comment in OOIntegrator contract
        vm.expectRevert();
        kpiManager.init(
            _orchestrator,
            _METADATA,
            abi.encode(address(stakingToken), address(0))
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__AlreadyInitialized);
        kpiManager.init(_orchestrator, _METADATA, bytes(""));
    }

    function createDummyKPI() public {
        uint[] memory trancheValues = new uint[](3);
        uint[] memory trancheRewards = new uint[](3);

        trancheValues[0] = 100;
        trancheValues[1] = 200;
        trancheValues[2] = 300;

        trancheRewards[0] = 100e18;
        trancheRewards[1] = 100e18;
        trancheRewards[2] = 100e18;

        kpiManager.createKPI(true, trancheValues, trancheRewards);
    }

    function setUpStakers(address[] memory users, uint[] memory amounts)
        public
        returns (uint totalUserFunds)
    {
        vm.assume(users.length < kpiManager.MAX_QUEUE_LENGTH());
        vm.assume(amounts.length >= users.length);

        _assumeValidAddresses(users);

        totalUserFunds = 0;

        for (uint i = 0; i < users.length; i++) {
            amounts[i] = bound(amounts[i], 1, 100_000_000e18);
            stakingToken.mint(users[i], amounts[i]);
            vm.startPrank(users[i]);
            stakingToken.approve(address(kpiManager), amounts[i]);
            kpiManager.stake(amounts[i]);
            totalUserFunds += amounts[i];
            vm.stopPrank();
        }

        // return totalUserFunds
    }
}

/*
postAssertionTest
├── when stakingQueue length is bigger than 0
│   └── it should stake all orders in the stakingQueue
├── it should delete the stakingQueue
├── it should set the queued funds to zero
├── when there aren't enough funds to pay the assertion fee
│   └── it should revert
└── when there are enough funds to pay the assertion fee
    ├── it should post a valid assertion in the UMA oracle
    ├── it should store the RewardRound configuration
    └── it should return a correct assertionId
*/

//TODO
contract KPIRewarder_postAssertionTest is KPIRewarderTest {
    function test_WhenStakingQueueLengthIsBiggerThan0(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should stake all orders in the stakingQueue
        uint totalUserFunds = setUpStakers(users, amounts);

        // prepare conditions
        createDummyKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            0
        );

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        ); //
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        //todo expectEmit
        // -emit Staked(depositFor, amount) for each user
        // -emit DataAsserted(dataId, data, asserter, assertionId);
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        for (uint i = 0; i < users.length; i++) {
            vm.expectEmit(true, true, true, true, address(kpiManager));
            emit Staked(users[i], amounts[i]);
        }
        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); //we don't know the last one

        bytes32 assertionId = kpiManager.postAssertion();
        vm.stopPrank();

        // state after
        assertEq(kpiManager.getStakingQueue().length, 0);
        assertEq(kpiManager.totalQueuedFunds(), 0);

        for (uint i = 0; i < users.length; i++) {
            assertEq(stakingToken.balanceOf(users[i]), 0);
        }

        assertEq(feeToken.balanceOf(MOCK_ASSERTER_ADDRESS), 0);

        //todo check mock for posted data
        IOptimisticOracleIntegrator.DataAssertion memory assertion =
            kpiManager.getAssertion(assertionId);
        IKPIRewarder.RewardRoundConfiguration memory rewardRoundConfig =
            kpiManager.getAssertionConfig(assertionId);

        assertEq(assertion.dataId, MOCK_ASSERTION_DATA_ID);
        assertEq(assertion.data, MOCK_ASSERTION_DATA);
        assertEq(assertion.asserter, MOCK_ASSERTER_ADDRESS);

        assertEq(rewardRoundConfig.creationTime, block.timestamp);
        assertEq(rewardRoundConfig.assertedValue, 100);
        assertEq(rewardRoundConfig.KpiToUse, 0);
        assertEq(rewardRoundConfig.distributed, false);
    }

    function test_ShoulDeleteTheStakingQueue() external {
        // it should delete the stakingQueue

        //tested in test_WhenStakingQueueLengthIsBiggerThan0
    }

    function test_ShouldSetTheQueuedFundsToZero() external {
        // it should set the queued funds to zero

        //tested in test_WhenStakingQueueLengthIsBiggerThan0
    }

    function test_WhenStakingQueueLengthIsEmpty() external {
        // prepare conditions
        createDummyKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            0
        );

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        ); //
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        //todo expectEmit
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        bytes32 assertionId = kpiManager.postAssertion();

        // state after
        assertEq(kpiManager.getStakingQueue().length, 0);
        assertEq(kpiManager.totalQueuedFunds(), 0);

        assertEq(feeToken.balanceOf(MOCK_ASSERTER_ADDRESS), 0);

        //todo check mock for posted data
        IOptimisticOracleIntegrator.DataAssertion memory assertion =
            kpiManager.getAssertion(assertionId);
        IKPIRewarder.RewardRoundConfiguration memory rewardRoundConfig =
            kpiManager.getAssertionConfig(assertionId);

        assertEq(assertion.dataId, MOCK_ASSERTION_DATA_ID);
        assertEq(assertion.data, MOCK_ASSERTION_DATA);
        assertEq(assertion.asserter, MOCK_ASSERTER_ADDRESS);

        assertEq(rewardRoundConfig.creationTime, block.timestamp);
        assertEq(rewardRoundConfig.assertedValue, 100);
        assertEq(rewardRoundConfig.KpiToUse, 0);
        assertEq(rewardRoundConfig.distributed, false);
    }

    function test_RevertWhen_ThereArentEnoughFundsToPayTheAssertionFee(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should revert

        uint totalUserFunds = setUpStakers(users, amounts);

        _assumeValidAddresses(users);

        // it should stake all orders in the stakingQueue

        // prepare conditions
        createDummyKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            0
        );

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken)) - 1
        ); //
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // SuT
        vm.prank(address(MOCK_ASSERTER_ADDRESS));
        vm.expectRevert(); // ERC20 insufficient balance revert
        bytes32 assertionId = kpiManager.postAssertion();

        // state after
        assertEq(kpiManager.getStakingQueue().length, users.length);
        assertEq(kpiManager.totalQueuedFunds(), totalUserFunds);

        for (uint i = 0; i < users.length; i++) {
            assertEq(kpiManager.stakingQueueAmounts(users[i]), amounts[i]);
        }

        assertEq(
            feeToken.balanceOf(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken)) - 1
        );
    }

    function test_WhenThereAreEnoughFundsToPayTheAssertionFee() external {
        // it should post a valid assertion in the UMA oracle
        // it should store the RewardRound configuration
        // it should return a correct assertionId

        //tested in test_WhenStakingQueueLengthIsBiggerThan0
    }
}
/*
createKPITest
├── when the number of tranches is 0
│   └── it should revert
├── when the number of tranches is bigger than 20
│   └── it should revert
├── when the length of the trancheValue array and the trancheReward array don't match
│   └── it should revert
├── when the values in the trancheValue array aren't incremental
│   └── it should revert
└── when the input is valid
    └── it should create a KPI struct with the currentKPI counter as ID and increase the counter


*/

contract KPIRewarder_createKPITest is KPIRewarderTest {
    function test_RevertWhen_TheNumberOfTranchesIs0() external {
        // it should revert

        uint[] memory trancheValues;
        uint[] memory trancheRewards;

        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidTrancheNumber.selector
        );
        kpiManager.createKPI(true, trancheValues, trancheRewards);
    }

    function test_RevertWhen_TheNumberOfTranchesIsBiggerThan20(
        uint[] calldata trancheValues,
        uint[] calldata trancheRewards
    ) external {
        // it should revert
        vm.assume(trancheValues.length >= 21);

        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidTrancheNumber.selector
        );
        kpiManager.createKPI(true, trancheValues, trancheRewards);
    }

    function test_RevertWhen_TheLengthOfTheTrancheValueArrayAndTheTrancheRewardArrayDontMatch(
        uint rewardLength,
        uint valueLength
    ) external {
        // it should revert
        rewardLength = bound(rewardLength, 1, 20);
        valueLength = bound(valueLength, 1, 20);

        vm.assume(rewardLength != valueLength);

        if (rewardLength != valueLength) {
            vm.expectRevert(
                IKPIRewarder
                    .Module__KPIRewarder__InvalidKPIValueLengths
                    .selector
            );
            kpiManager.createKPI(
                true, new uint[](valueLength), new uint[](rewardLength)
            );
        }
    }

    function test_RevertWhen_TheValuesInTheTrancheValueArrayArentIncremental(
        uint[] calldata trancheValues,
        uint[] calldata trancheRewards
    ) external {
        vm.assume(trancheValues.length >= 2);
        vm.assume(trancheRewards.length >= trancheValues.length);

        uint length = bound(trancheValues.length, 2, 20);

        uint[] memory valuesCapped = trancheValues[0:length];
        uint[] memory rewardsCapped = trancheRewards[0:length];

        for (uint i = 0; i < length; i++) {
            //bound values to avoid overflows
            valuesCapped[i] =
                bound(valuesCapped[i], 1, 1_000_000_000_000_000e18);
            rewardsCapped[i] =
                bound(rewardsCapped[i], 1e18, 1_000_000_000_000_000e18);
        }

        //console.log(valuesCapped.length);
        //console.log(rewardsCapped.length);

        valuesCapped[length - 1] = valuesCapped[length - 2] / 2; // this avoids overflows etc, and also activates the case where two tranches have the same value

        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidKPITrancheValues.selector
        );
        kpiManager.createKPI(true, valuesCapped, rewardsCapped);

        // it should revert
    }

    function test_WhenTheInputIsValid(
        bool continuous,
        uint numOfTranches,
        uint trancheSeed,
        uint rewardSeed
    ) external {
        // it should create a KPI struct with the currentKPI counter as ID and increase the counter

        numOfTranches = bound(numOfTranches, 1, 20);
        trancheSeed = bound(trancheSeed, 1, 10_000);
        rewardSeed = bound(rewardSeed, 1e18, 1000e18);

        uint[] memory trancheValues = new uint[](numOfTranches);
        uint[] memory trancheRewards = new uint[](numOfTranches);

        for (uint i = 0; i < numOfTranches; i++) {
            trancheValues[i] = trancheSeed * (i + 1);
            trancheRewards[i] = rewardSeed * (i + 1);
        }

        uint kpiNum =
            kpiManager.createKPI(continuous, trancheValues, trancheRewards);

        // TODO check event emission

        IKPIRewarder.KPI memory generatedKPI = kpiManager.getKPI(kpiNum);

        assertEq(generatedKPI.creationTime, block.timestamp);
        assertEq(generatedKPI.trancheValues.length, numOfTranches);
        assertEq(generatedKPI.trancheRewards.length, numOfTranches);
        assertEq(generatedKPI.continuous, continuous);

        for (uint i = 0; i < numOfTranches; i++) {
            assertEq(generatedKPI.trancheValues[i], trancheValues[i]);
            assertEq(generatedKPI.trancheRewards[i], trancheRewards[i]);
        }
    }
}

/*
setKPITest
├── when the KPI number is above the current KPI
│   └── it should revert
└── when the KPI number is among the existing KPIs
    └── it should change the activeKPI to the given KPI
*/

contract KPIRewarder_setKPITest is KPIRewarderTest {
    function test_RevertWhen_TheKPINumberIsAboveTheCurrentKPI(uint KPInum)
        external
    {
        // it should revert
        vm.assume(KPInum > kpiManager.KPICounter());

        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidKPINumber.selector
        );
        kpiManager.setKPI(KPInum);
    }

    function test_WhenTheKPINumberIsAmongTheExistingKPIs(uint KPInum)
        external
    {
        for (uint i = 0; i < 5; i++) {
            createDummyKPI();
        }
        // it should change the activeKPI to the given KPI
        KPInum = bound(KPInum, 0, kpiManager.KPICounter() - 1);

        kpiManager.setKPI(KPInum);

        assertEq(kpiManager.activeKPI(), KPInum);
    }
}

/*
//TODO review for changes in contract
stakeTest
├── when the staked amount is 0
│   └── it should revert
├── when the length of the staking Queue is already at MAX_QUEUE_LENGTH
│   └── it should revert
├── when the caller does not have sufficient funds
│   └── it should revert
└── when the caller has sufficient funds
    └── it should store the amount + caller in the staking Queue and increase the value of totalQueuedFunds by the staked amount
*/
contract KPIRewarder_stakeTest is KPIRewarderTest {
    function test_RevertWhen_TheStakedAmountIs0() external {
        // it should revert

        stakingToken.mint(USER_1, 1000e18);
        vm.startPrank(USER_1);
        stakingToken.approve(address(kpiManager), 1000e18);
        vm.expectRevert(
            IERC20PaymentClient
                .Module__ERC20PaymentClient__InvalidAmount
                .selector
        );
        kpiManager.stake(0);
    }

    function test_RevertWhen_TheLengthOfTheStakingQueueIsAlreadyAtMAX_QUEUE_LENGTH(
        uint[] calldata amounts
    ) external {
        // it should revert
        address USER;
        vm.assume(amounts.length > kpiManager.MAX_QUEUE_LENGTH());
        for (uint i = 0; i < kpiManager.MAX_QUEUE_LENGTH(); i++) {
            USER = address(uint160(i + 1));
            uint amount = bound(amounts[i], 1, 1_000_000e18);
            stakingToken.mint(USER, amount);
            vm.startPrank(USER);
            stakingToken.approve(address(kpiManager), amount);

            kpiManager.stake(amount);
            vm.stopPrank();
        }

        USER = address(0x1337);
        stakingToken.mint(USER, 1000e18);
        vm.startPrank(USER);
        stakingToken.approve(address(kpiManager), 1000e18);
        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__StakingQueueIsFull.selector
        );
        kpiManager.stake(1000e18);
        vm.stopPrank();
    }

    function test_RevertWhen_TheCallerDoesNotHaveSufficientFunds() external {
        // it should revert

        address USER = address(0x1337);
        stakingToken.mint(USER, 1e18);
        vm.startPrank(USER);
        stakingToken.approve(address(kpiManager), 1000e18);
        vm.expectRevert();
        kpiManager.stake(1000e18);
        vm.stopPrank();
    }

    function test_WhenTheCallerHasSufficientFunds(uint amount) external {
        // it should store the amount + caller in the staking Queue and increase the value of totalQueuedFunds by the staked amount

        amount = bound(amount, 1, 100_000e18);
        address USER = address(0x1337);

        // state before
        uint stakingQueueLengthBefore = kpiManager.getStakingQueue().length;
        uint userStakeBalanceBefore = kpiManager.stakingQueueAmounts(USER);
        uint totalQueuedFundsBefore = kpiManager.totalQueuedFunds();

        stakingToken.mint(USER, amount);
        vm.startPrank(USER);
        stakingToken.approve(address(kpiManager), amount);
        kpiManager.stake(amount);
        vm.stopPrank();

        // state after
        assertEq(
            kpiManager.getStakingQueue().length, stakingQueueLengthBefore + 1
        );
        assertEq(
            kpiManager.stakingQueueAmounts(USER),
            userStakeBalanceBefore + amount
        );
        assertEq(kpiManager.totalQueuedFunds(), totalQueuedFundsBefore + amount);
    }
}

/*
assertionresolvedCallbackTest
├── when the assertion resolved to false
│   └── it should emit an event
└── when the assertion resolved to true
    ├── it will go through all tranches until reaching the asserted amount
    ├── when the rewardType is continuous
    │   └── it should pay out an amount from the last tranche proportional to its level of completion
    ├── when the rewardType is not continuous
    │   └── it should not pay out any amount from the uncompleted tranche at all
    ├── it should set the staking rewards to the calculated value with a duration of 1
    └── it should emit an event

    // TODO if the caller is not OO

*/
//TODO

contract KPIRewarder_assertionresolvedCallbackTest is KPIRewarderTest {
    function setUpStateForAssertionResolution(
        address[] memory users,
        uint[] memory amounts
    ) public returns (bytes32 assertionId) {
        // it should stake all orders in the stakingQueue
        uint totalUserFunds = setUpStakers(users, amounts);

        // prepare conditions
        createDummyKPI();

        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            0
        );

        // prepare  bond and asserter authorization
        kpiManager.grantModuleRole(
            kpiManager.ASSERTER_ROLE(), MOCK_ASSERTER_ADDRESS
        );
        feeToken.mint(
            address(MOCK_ASSERTER_ADDRESS),
            ooV3.getMinimumBond(address(feeToken))
        ); //
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        feeToken.approve(
            address(kpiManager), ooV3.getMinimumBond(address(feeToken))
        );
        vm.stopPrank();

        // stake user funds
        for (uint i = 0; i < users.length; i++) {
            amounts[i] = bound(amounts[i], 1, 100_000_000e18);
            stakingToken.mint(users[i], amounts[i]);
            vm.startPrank(users[i]);
            stakingToken.approve(address(kpiManager), amounts[i]);
            kpiManager.stake(amounts[i]);
            vm.stopPrank();
        }

        // SuT
        //todo expectEmit
        // -emit Staked(depositFor, amount) for each user
        // -emit DataAsserted(dataId, data, asserter, assertionId);
        vm.startPrank(address(MOCK_ASSERTER_ADDRESS));
        for (uint i = 0; i < users.length; i++) {
            vm.expectEmit(true, true, true, true, address(kpiManager));
            emit Staked(users[i], amounts[i]);
        }
        vm.expectEmit(true, false, false, false, address(kpiManager));
        emit DataAsserted(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            0x0
        ); //we don't know the last one

        bytes32 assertionId = kpiManager.postAssertion();
        vm.stopPrank();

        return assertionId;
    }

    function test_WhenTheAssertionResolvedToFalse(
        address[] memory users,
        uint[] memory amounts
    ) external {
        // it should emit an event
        bytes32 createdID = setUpStateForAssertionResolution(users, amounts);

        vm.startPrank(address(ooV3));
        //vm.expectEmit(true, true, true, true, address(kpiManager));
         vm.expectEmit(false, false, false, false, address(kpiManager));
       
        emit DataAssertionResolved(
            false,
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            createdID
        );
        kpiManager.assertionResolvedCallback(createdID, false);
        vm.stopPrank();
    }

    modifier whenTheAssertionResolvedToTrue() {
        // set up KPI
        // set UP assertion
        // speedrun assertion resolution

        _;
    }

    function test_WhenTheAssertionResolvedToTrue()
        external
        whenTheAssertionResolvedToTrue
    {
        // since its the first assertion, id should be zero.

        // it will go through all tranches until reaching the asserted amount
        // it should set the staking rewards to the calculated value with a duration of 1
        // it should emit an event
    }

    function test_WhenTheRewardTypeIsContinuous()
        external
        whenTheAssertionResolvedToTrue
    {
        // it should pay out an amount from the last tranche proportional to its level of completion
    }

    function test_WhenTheRewardTypeIsNotContinuous()
        external
        whenTheAssertionResolvedToTrue
    {
        // it should not pay out any amount from the uncompleted tranche at all
    }
}

/*
prepareAsertionTest
├── when the target KPI is not valid
│   └── it should revert
└── when the asserter targetValue is not valid
    └── it should revert
*/

contract KPIRewarder_setAssertionTest is KPIRewarderTest {
    function test_RevertWhen_TheTargetKPIIsNotValid() external {
        // it should revert
        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidKPINumber.selector
        );
        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            100,
            99_999
        );
    }

    function test_RevertWhen_TheTargetValueIsNotValid() external {
        // it should revert
        vm.expectRevert(
            IKPIRewarder.Module__KPIRewarder__InvalidTargetValue.selector
        );
        kpiManager.prepareAssertion(
            MOCK_ASSERTION_DATA_ID,
            MOCK_ASSERTION_DATA,
            MOCK_ASSERTER_ADDRESS,
            0,
            0
        );
    }
}