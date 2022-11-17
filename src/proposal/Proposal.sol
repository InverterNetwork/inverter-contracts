// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// External Dependencies
// @todo mp: Would like to have 2 step owner.
import {OwnableUpgradeable} from "@oz-up/access/OwnableUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@oz-up/security/PausableUpgradeable.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from
    "@oz-up/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";
import {ModuleManager} from "src/proposal/base/ModuleManager.sol";
import {ContributorManager} from "src/proposal/base/ContributorManager.sol";
import {FundingVault} from "src/proposal/base/FundingVault.sol";

// Internal Interfaces
import {
    IProposal,
    IPaymentProcessor,
    IAuthorizer
} from "src/proposal/IProposal.sol";

/**
 * @title Proposal
 *
 * @dev
 *
 * @author byterocket
 */
contract Proposal is
    IProposal,
    OwnableUpgradeable,
    PausableUpgradeable,
    ModuleManager,
    ContributorManager,
    FundingVault
{
    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice Modifier to guarantee function is only callable by authorized
    ///         address.
    modifier onlyOwnerOrAuthorized() {
        if (!_isOwnerOrAuthorized(msg.sender)) {
            revert Proposal__CallerNotAuthorized();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Storage

    /// @inheritdoc IProposal
    uint public override (IProposal) proposalId;

    /// @inheritdoc IProposal
    IERC20 public override (IProposal) token;

    /// @inheritdoc IProposal
    IAuthorizer public override (IProposal) authorizer;

    /// @inheritdoc IProposal
    IPaymentProcessor public override (IProposal) paymentProcessor;

    //--------------------------------------------------------------------------
    // Initializer

    // @todo CHECK!!!
    ///// @custom:oz-upgrades-unsafe-allow constructor
    //constructor() {
    //    _disableInitializers();
    //}

    /// @inheritdoc IProposal
    function init(
        uint proposalId_,
        address owner_,
        IERC20 token_,
        address[] calldata modules,
        IAuthorizer authorizer_,
        IPaymentProcessor paymentProcessor_
    ) external override (IProposal) initializer {
        // Initialize upstream contracts.
        __Pausable_init();
        __Ownable_init();
        __ModuleManager_init(modules);
        __ContributorManager_init();
        __FundingVault_init(
            proposalId_, IERC20MetadataUpgradeable(address(token_))
        );

        // Set storage variables.
        proposalId = proposalId_;
        _transferOwnership(owner_);
        token = token_;
        authorizer = authorizer_;
        paymentProcessor = paymentProcessor_;

        // Add necessary modules.
        // Note to not use the public addModule function as the factory
        // is (most probably) not authorized.
        __ModuleManager_addModule(address(authorizer_));
        __ModuleManager_addModule(address(paymentProcessor_));
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    function __ModuleManager_isAuthorized(address who)
        internal
        view
        override (ModuleManager)
        returns (bool)
    {
        // @todo Not tested
        return _isOwnerOrAuthorized(who);
    }

    function __ContributorManager_isAuthorized(address who)
        internal
        view
        override (ContributorManager)
        returns (bool)
    {
        return _isOwnerOrAuthorized(who);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IProposal
    function executeTx(address target, bytes memory data)
        external
        onlyOwnerOrAuthorized
        returns (bytes memory)
    {
        bool ok;
        bytes memory returnData;
        (ok, returnData) = target.call(data);

        if (ok) {
            // @todo Not tested
            return returnData;
        } else {
            // @todo Not tested
            revert Proposal__ExecuteTxFailed();
        }
    }

    /// @inheritdoc IProposal
    function version() external pure returns (string memory) {
        return "1";
    }

    function owner()
        public
        view
        override (OwnableUpgradeable, IProposal)
        returns (address)
    {
        return super.owner();
    }

    function paused()
        public
        view
        override (PausableUpgradeable, IProposal)
        returns (bool)
    {
        return super.paused();
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function _isOwnerOrAuthorized(address who) private view returns (bool) {
        return authorizer.isAuthorized(who) || owner() == who;
    }
}
