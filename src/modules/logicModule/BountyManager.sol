// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";

import {PaymentClient} from "src/modules/base/mixins/PaymentClient.sol";

// Internal Interfaces
import {IProposal} from "src/proposal/IProposal.sol";
import {IBountyManager} from "src/modules/logicModule/IBountyManager.sol";

import {
    IPaymentClient,
    IPaymentProcessor
} from "src/modules/base/mixins/PaymentClient.sol";

// Internal Libraries
import {LinkedIdList} from "src/common/LinkedIdList.sol";

contract BountyManager is IBountyManager, Module, PaymentClient {
    using SafeERC20 for IERC20;
    using LinkedIdList for LinkedIdList.List;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier validPayoutAmounts(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount
    ) {
        if (
            minimumPayoutAmount == 0 || maximumPayoutAmount == 0
                || maximumPayoutAmount < minimumPayoutAmount
        ) {
            revert Module__BountyManager__InvalidPayoutAmounts();
        }
        _;
    }

    modifier validBountyId(uint bountyId) {
        if (!isExistingBountyId(bountyId)) {
            revert Module__BountyManager__InvalidBountyId();
        }
        _;
    }

    modifier validClaimId(uint claimId) {
        if (!isExistingClaimId(claimId)) {
            revert Module__BountyManager__InvalidClaimId();
        }
        _;
    }

    function validContributorsForBounty(
        Contributor[] memory contributors,
        Bounty memory bounty
    ) internal view {
        //@update to be in correct range
        uint length = contributors.length;
        //length cant be zero
        if (length == 0) {
            revert Module__BountyManager__InvalidContributorsLength();
        }
        uint totalAmount;
        uint currentAmount;
        address contrib;
        for (uint i; i < length; i++) {
            currentAmount = contributors[i].claimAmount;

            //amount cant be zero
            if (currentAmount == 0) {
                revert Module__BountyManager__InvalidContributorAmount();
            }

            contrib = contributors[i].addr;
            if (
                contrib == address(0) || contrib == address(this)
                    || contrib == address(proposal())
            ) {
                revert Module__BountyManager__InvalidContributorAddress();
            }

            totalAmount += currentAmount;
        }

        if (
            totalAmount > bounty.maximumPayoutAmount
                || totalAmount < bounty.minimumPayoutAmount
        ) {
            revert Module__BountyManager__ClaimExceedsGivenPayoutAmounts();
        }
    }

    modifier accordingClaimToBounty(uint claimId, uint bountyId) {
        //Its not claimed if claimedBy is still 0
        if (_claimRegistry[claimId].bountyId != bountyId) {
            revert Module__BountyManager__NotAccordingClaimToBounty();
        }
        _;
    }

    modifier notClaimed(uint bountyId) {
        //Its not claimed if claimedBy is still 0
        if (_bountyRegistry[bountyId].claimedBy != 0) {
            revert Module__BountyManager__BountyAlreadyClaimed();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Marks the beginning of the list.
    uint internal constant _SENTINEL = type(uint).max;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Value for what the next id will be.
    uint private _nextId;

    /// @dev Registry mapping ids to Bounty structs.
    mapping(uint => Bounty) private _bountyRegistry;

    /// @dev List of Bounty id's.
    LinkedIdList.List _bountyList;

    /// @dev Registry mapping ids to Claim structs.
    mapping(uint => Claim) private _claimRegistry;

    /// @dev List of Bounty id's.
    LinkedIdList.List _claimList;

    //@dev Connects contributor addresses to claim Ids
    mapping(address => uint[]) contributorAddressToClaimIds;
    //--------------------------------------------------------------------------
    // Initialization

    /// @inheritdoc Module
    function init(IProposal proposal_, Metadata memory metadata, bytes memory)
        external
        override(Module)
        initializer
    {
        __Module_init(proposal_, metadata);
        //init empty list of bounties and claims
        _bountyList.init();
        _claimList.init();
    }

    //--------------------------------------------------------------------------
    // Getter Functions

    /// @inheritdoc IBountyManager
    function getBountyInformation(uint bountyId)
        external
        view
        validBountyId(bountyId)
        returns (Bounty memory)
    {
        return _bountyRegistry[bountyId];
    }

    /// @inheritdoc IBountyManager
    function listBountyIds() external view returns (uint[] memory) {
        return _bountyList.listIds();
    }

    /// @inheritdoc IBountyManager
    function isExistingBountyId(uint bountyId) public view returns (bool) {
        return _bountyList.isExistingId(bountyId);
    }

    /// @inheritdoc IBountyManager
    function getClaimInformation(uint claimId)
        external
        view
        validClaimId(claimId)
        returns (Claim memory)
    {
        return _claimRegistry[claimId];
    }

    /// @inheritdoc IBountyManager
    function listClaimIds() external view returns (uint[] memory) {
        return _claimList.listIds();
    }

    /// @inheritdoc IBountyManager
    function isExistingClaimId(uint claimId) public view returns (bool) {
        return _claimList.isExistingId(claimId);
    }

    /// @inheritdoc IBountyManager
    function listClaimIdsForContributorAddress(
        address contributorAddrs //@todo test for empty
    ) external view returns (uint[] memory) {
        return contributorAddressToClaimIds[contributorAddrs];
    }

    //--------------------------------------------------------------------------
    // Mutating Functions

    /// @inheritdoc IBountyManager
    function addBounty(
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    )
        external
        //@todo restrict to appropriate role
        validPayoutAmounts(minimumPayoutAmount, maximumPayoutAmount)
        returns (uint id)
    {
        // Note ids start at 1.
        uint bountyId = ++_nextId;

        // Add Bounty id to the list.
        _bountyList.addId(bountyId);

        Bounty storage b = _bountyRegistry[bountyId];

        b.minimumPayoutAmount = minimumPayoutAmount;
        b.maximumPayoutAmount = maximumPayoutAmount;
        b.details = details;

        emit BountyAdded(
            bountyId, minimumPayoutAmount, maximumPayoutAmount, details
        );

        return bountyId;
    }

    /// @inheritdoc IBountyManager
    function updateBounty(
        uint bountyId,
        uint minimumPayoutAmount,
        uint maximumPayoutAmount,
        bytes calldata details
    )
        external
        //@todo update access
        validBountyId(bountyId)
        validPayoutAmounts(minimumPayoutAmount, maximumPayoutAmount)
    {
        Bounty storage b = _bountyRegistry[bountyId];

        b.minimumPayoutAmount = minimumPayoutAmount;
        b.maximumPayoutAmount = maximumPayoutAmount;
        b.details = details;

        emit BountyUpdated(
            bountyId, minimumPayoutAmount, maximumPayoutAmount, details
        );
    }

    /// @inheritdoc IBountyManager
    function addClaim(
        uint bountyId,
        Contributor[] calldata contributors,
        bytes calldata details
    )
        external
        //@todo restrict to appropriate role
        validBountyId(bountyId)
        returns (uint id)
    {
        validContributorsForBounty(contributors, _bountyRegistry[bountyId]);
        // Note ids start at 1.
        uint claimId = ++_nextId;

        // Add Claim id to the list.
        _claimList.addId(claimId);

        Claim storage c = _claimRegistry[claimId];

        // Add Claim instance to registry.
        c.bountyId = bountyId;

        uint length = contributors.length;
        for (uint i; i < length; ++i) {
            c.contributors.push(contributors[i]);
            //add ClaimId to each contributor address accoringly//@todo take a look here /mirrored on the update Function?
            contributorAddressToClaimIds[contributors[i].addr].push(claimId);
        }

        c.details = details;

        emit ClaimAdded(claimId, bountyId, contributors, details);

        return claimId;
    }

    /// @inheritdoc IBountyManager
    function updateClaim(
        uint claimId,
        uint bountyId,
        Contributor[] calldata contributors,
        bytes calldata details
    )
        external
        //@todo update access
        validClaimId(claimId)
        validBountyId(bountyId)
    {
        validContributorsForBounty(contributors, _bountyRegistry[bountyId]);
        Claim storage c = _claimRegistry[claimId];

        c.bountyId = bountyId;

        delete c.contributors;

        uint length = contributors.length; //@todo Do a seperate version for just updating contributors? gas inefficient
        for (uint i; i < length; ++i) {
            c.contributors.push(contributors[i]);
        }

        c.details = details;

        emit ClaimUpdated(claimId, bountyId, contributors, details);
    }

    /// @inheritdoc IBountyManager
    function verifyClaim(uint claimId, uint bountyId)
        external
        validClaimId(claimId)
        validBountyId(bountyId)
        accordingClaimToBounty(claimId, bountyId)
        notClaimed(bountyId)
    //@todo access
    {
        Contributor[] memory contribs = _claimRegistry[claimId].contributors;

        uint length = contribs.length;

        //total amount needed to verifyBounty
        uint totalAmount;

        //current contributor in loop
        Contributor memory contrib;

        //For each Contributor add payments according to the claimAmount specified
        for (uint i; i < length; i++) {
            contrib = contribs[i];
            totalAmount += contrib.claimAmount;

            _addPaymentOrder(
                contrib.addr,
                contrib.claimAmount,
                block.timestamp //dueTo Date is now
            );
        }

        //ensure that this contract has enough tokens to fulfill all payments
        _ensureTokenBalance(totalAmount);

        //when done process the Payments correctly
        __Module_proposal.paymentProcessor().processPayments(
            IPaymentClient(address(this))
        );

        //Set completed to true
        _bountyRegistry[bountyId].claimedBy = claimId;

        emit ClaimVerified(claimId, bountyId);
    }

    //--------------------------------------------------------------------------
    // {PaymentClient} Function Implementations

    function _ensureTokenBalance(uint amount)
        internal
        override(PaymentClient)
    {
        uint balance = __Module_proposal.token().balanceOf(address(this));

        if (balance < amount) {
            // Trigger callback from proposal to transfer tokens
            // to address(this).
            bool ok;
            (ok, /*returnData*/ ) = __Module_proposal.executeTxFromModule(
                address(__Module_proposal.fundingManager()),
                abi.encodeWithSignature(
                    "transferProposalToken(address,uint256)",
                    address(this),
                    amount - balance
                )
            );

            if (!ok) {
                revert Module__PaymentClient__TokenTransferFailed();
            }
        }
    }

    function _ensureTokenAllowance(IPaymentProcessor spender, uint amount)
        internal
        override(PaymentClient)
    {
        IERC20 token = __Module_proposal.token();
        uint allowance = token.allowance(address(this), address(spender));

        if (allowance < amount) {
            token.safeIncreaseAllowance(address(spender), amount - allowance);
        }
    }

    function _isAuthorizedPaymentProcessor(IPaymentProcessor who)
        internal
        view
        override(PaymentClient)
        returns (bool)
    {
        return __Module_proposal.paymentProcessor() == who;
    }
}