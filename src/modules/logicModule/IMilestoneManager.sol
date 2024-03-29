// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IPaymentClient} from "src/modules/base/mixins/IPaymentClient.sol";

interface IMilestoneManager is IPaymentClient {
    //--------------------------------------------------------------------------
    // Types

    struct Milestone {
        /// @dev The duration of the milestone.
        ///      MUST not be zero.
        uint duration;
        /// @dev The budget for the milestone.
        ///      That is the number of tokens payed to contributors when the
        ///      milestone starts.
        ///      CAN be zero.
        uint budget;
        /// @dev The contributors for the Milestone
        ///      MUST not be empty
        ///      All contributors.salary MUST add up to 100_000_000 (100%)
        Contributor[] contributors;
        /// @dev Arbitrary data to store milestone details if necessary.
        ///      CAN be empty.
        bytes details;
        /// @dev The timestamp the milestone started.
        uint startTimestamp;
        /// @dev Represents the data that is accompanied when a milestone is submitted.
        ///      A Milestone is interpreted as being submitted when the
        ///      submissionData bytes array is not empty.
        ///      Note that only accounts holding the {CONTRIBUTOR_ROLE()} can
        ///      set submittedData and therefore submit milestones.
        bytes submissionData;
        /// @dev Whether the milestone is completed.
        ///      A milestone is completed if it got confirmed and started more
        ///      than duration seconds ago.
        bool completed;
        /// @dev The milestone's last updated timestamp
        ///      To start a new milestone, it should not have been updated in the last 5 days
        uint lastUpdatedTimestamp;
    }

    struct Contributor {
        /// @dev The contributor's address.
        ///      MUST not be empty.
        address addr;
        /// @dev The contributor's salary, as a percentage of the Milestone's total budget.
        ///      MUST not be empty.
        ///      MUST be a number between 1 and SALARY_PRECISION.
        /// @dev Default value for SALARY_PRECISION is 100_000_000 This allows precision of up to 1$ in a 1.000.000$ budget.
        uint salary;
        /// @dev Additional data for the contributor.
        ///      CAN be empty.
        bytes32 data;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by contributor.
    error Module__MilestoneManager__OnlyCallableByContributor();

    /// @notice Given duration invalid.
    error Module__MilestoneManager__InvalidDuration();

    /// @notice Given budget invalid.
    //error Module__MilestoneManager__InvalidBudget();

    /// @notice Given details invalid.
    error Module__MilestoneManager__InvalidDetails();

    /// @notice Given position invalid.
    error Module__MilestoneManager__InvalidPosition();

    /// @notice Given id is not a valid Intermediate Position in list.
    error Module__MilestoneManager__InvalidMilestonePositionShift();

    /// @notice Given milestone id invalid.
    error Module__MilestoneManager__InvalidMilestoneId();

    /// @dev The given submissionData is invalid
    error Module__MilestoneManage__InvalidSubmissionData();

    /// @notice Given milestone not updateable.
    error Module__MilestoneManager__MilestoneNotUpdateable();

    /// @notice Given milestone not removable.
    error Module__MilestoneManager__MilestoneNotRemovable();

    // @notice Given milestone not active.
    error Module__MilestoneManager__MilestoneNotActive();

    /// @notice Given milestone not submitable.
    error Module__MilestoneManager__MilestoneNotSubmitable();

    /// @notice Given milestone not completed.
    error Module__MilestoneManager__MilestoneNotCompleteable();

    /// @notice Given milestone not declineable.
    error Module__MilestoneManager__MilestoneNotDeclineable();

    /// @notice Given milestone not activateable.
    error Module__MilestoneManager__MilestoneNotActivateable();

    /// @notice The supplied milestones are not consecutive
    error Module__MilestoneManager__MilestonesNotConsecutive();

    /// @notice No active milestone currently existing.
    error Module__MilestoneManager__NoActiveMilestone();

    /// @notice Milestone has either too many or no contributors at all.
    error Module__MilestoneManager__InvalidContributorAmount();

    /// @notice Given contributor address invalid.
    error Module__MilestoneManager__InvalidContributorAddress();

    /// @notice Contributor address is already on list.
    error Module__MilestoneManager__DuplicateContributorAddress();

    /// @notice Given contributor salary invalid.
    error Module__MilestoneManager__InvalidContributorSalary();

    /// @notice Given contributor salary invalid.
    error Module__MilestoneManager__InvalidSalarySum();

    /// @notice The fee exceeds 100%
    error Module__MilestoneManager__FeeOverHundredPercent();

    /// @notice The function can only be called by the treasury
    error Module__MilestoneManager__OnlyCallableByTreasury();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when a new milestone added.
    event MilestoneAdded(
        uint indexed id,
        uint duration,
        uint budget,
        Contributor[] contributors,
        bytes details
    );

    /// @notice Event emitted when a milestone got updated.
    event MilestoneUpdated(
        uint indexed id,
        uint duration,
        uint budget,
        Contributor[] contributors,
        bytes details
    );

    /// @notice Event emitted when a milestone is stopped.
    // @param id id of the milestone that is stopped.
    event MilestoneStopped(uint indexed id);

    /// @notice Event emitted when a milestone is removed.
    event MilestoneRemoved(uint indexed id);

    /// @notice Event emitted when a milestone is started.
    event MilestoneStarted(uint indexed id);

    /// @notice Event emitted when a milestone is submitted.
    event MilestoneSubmitted(uint indexed id, bytes submissionData);

    /// @notice Event emitted when a milestone is completed.
    event MilestoneCompleted(uint indexed id);

    /// @notice Event emitted when a milestone declined.
    event MilestoneDeclined(uint indexed id);

    /// @notice Event emitted when a milestone updation timelock is updated.
    event MilestoneUpdateTimelockUpdated(uint indexed newTimelock);

    //--------------------------------------------------------------------------
    // Functions

    //----------------------------------
    // Milestone View Functions

    /// @notice Returns the milestone instance with id `id`.
    /// @dev Returns empty milestone in case id `id` is invalid.
    /// @param id The id of the milstone to return.
    /// @return Milestone with id `id`.
    function getMilestoneInformation(uint id)
        external
        view
        returns (Milestone memory);

    /// @notice Returns total list of milestone ids.
    /// @dev List is in ascending order.
    /// @return List of milestone ids.
    function listMilestoneIds() external view returns (uint[] memory);

    /// @notice Fetches the id of the previous milestone in the list
    /// @dev Reverts if id invalid
    /// @dev This should ideally be only used in a frontend context
    ///      because iterating through the list and finding the previous element
    ///      causes an O(n) runtime of the given list and should ideally be outsourced off-chain.
    /// @param id the id of which the previous element in the list should be found.
    /// @return prevId The id of the previous milestone.
    function getPreviousMilestoneId(uint id)
        external
        view
        returns (uint prevId);

    /// @notice Returns the current active milestone's id.
    /// @dev Reverts in case there is no active milestone.
    /// @return Current active milestone id.
    function getActiveMilestoneId() external view returns (uint);

    /// @notice Returns whether there exists a current active milestone.
    /// @return True if current active milestone exists, false otherwise.
    function hasActiveMilestone() external view returns (bool);

    /// @notice Returns whether the next milestone is activatable.
    /// @return True if next milestone activatable, false otherwise.
    function isNextMilestoneActivatable() external view returns (bool);

    /// @notice Returns whether milestone with id `id` exists.
    /// @return True if milestone with id `id` exists, false otherwise.
    function isExistingMilestoneId(uint id) external view returns (bool);

    /// @notice Returns whether an address is a contributor in one specific milestone.
    /// @return True if the address is a contributor, false otherwise.
    function isContributor(uint id, address who) external view returns (bool);

    /// @notice Returns the precision of the salary percentages. Should be read as "100 + digits after comma", representing 100%
    /// @return The salary precision
    function getSalaryPrecision() external view returns (uint);

    /// @notice Returns what part of the Budget gets taken as fee at the start of a Milestone.
    /// @return The fee, relative to the SALARY_PRECISION
    function getFeePct() external view returns (uint);

    /// @notice Returns the maximum number of allowed contributors
    /// @return The maximum contributors
    function getMaximumContributors() external pure returns (uint);

    //----------------------------------
    // Milestone Mutating Functions

    /// @notice Adds a new milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid.
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param contributors The contributor information for the milestone
    /// @param details The milestone's details.
    /// @return The newly added milestone's id.
    function addMilestone(
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external returns (uint);

    /// @notice Stops a milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone not currently active or milestone ids
    ///      not consecutive in list.
    /// @param prevId The previous milestone's id in the milestone list.
    /// @param id The milestone's id to remove.
    function stopMilestone(uint prevId, uint id) external;

    /// @notice Removes a milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone already completed or milestone ids
    ///      not consecutive in list.
    /// @param prevId The previous milestone's id in the milestone list.
    /// @param id The milestone's id to remove.
    function removeMilestone(uint prevId, uint id) external;

    /// @notice Starts the next milestones.
    /// @dev Creates the payment orders to pay contributors.
    /// @dev Reverts if next milestone not activatable or proposal's contributor
    ///      list empty.
    /// @dev Only callable by authorized addresses.
    function startNextMilestone() external;

    /// @notice Updates a milestone's informations.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if an argument invalid or milestone already started.
    /// @param id The milestone's id.
    /// @param duration The duration of the milestone.
    /// @param budget The budget for the milestone.
    /// @param contributors The contributor information for the milestone
    /// @param details The milestone's details.
    function updateMilestone(
        uint id,
        uint duration,
        uint budget,
        Contributor[] calldata contributors,
        bytes calldata details
    ) external;

    /// @notice Moves a Milestone in the milestone list
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if milestone that should be moved already started.
    /// @dev Reverts if the position following the idToPositionAfter milestone already started.
    /// @dev Reverts if milestone that should be moved equals the milestone that should be positioned after.
    /// @dev Reverts if milestone that should be positioned after equals the milestone that comes previous to the one that should be moved
    /// @param id The id of the milestone that should be moved.
    /// @param prevId The previous milestone's id in the milestone list (in relation to the milestone that should be moved).
    /// @param idToPositionAfter The id of the milestone, that the selected milestone should be positioned after.
    function moveMilestoneInList(uint id, uint prevId, uint idToPositionAfter)
        external;

    /// @notice Submits a milestone.
    /// @dev Only callable by addresses holding the contributor role.
    /// @dev Reverts if id invalid, milestone not yet started, or milestone
    ///      already completed.
    /// @dev Relay function that routes the function call via the proposal.
    /// @param id The milestone's id.
    function submitMilestone(uint id, bytes calldata submissionData) external;

    /// @notice Completes a milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid or milestone not yet submitted.
    /// @param id The milestone's id.
    function completeMilestone(uint id) external;

    /// @notice Declines a submitted milestone.
    /// @dev Only callable by authorized addresses.
    /// @dev Reverts if id invalid, milestone not yet submitted, or milestone
    ///      already completed.
    /// @param id The milestone's id.
    function declineMilestone(uint id) external;

    /// @notice Updates the `_milestoneUpdateTimelock` value
    /// @dev Only callable by authorized addresses.
    /// @dev The `_milestoneUpdateTimelock` is the allowed time gap between updating a milestone and starting it
    /// @param _newTimelock The new intended value for `_milestoneUpdateTimelock`
    function updateMilestoneUpdateTimelock(uint _newTimelock) external;
}
