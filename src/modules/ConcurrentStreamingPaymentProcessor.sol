// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

// Internal Dependencies
// @note paymentClient is a interface that provides functions pertaining to different payment orders, the list of remaining orders and fulfilling those orders etc.
//       struct paymentOrder is defined as {address recepient, uint256 amount, uint256 createdAt, uint256 dueTo}
// @note paymentProcessor can cancelPaymentOrders & fulfillPaymentOrders based on a particular instance of PaymentClient.
import {
    IPaymentProcessor,
    IPaymentClient
} from "src/modules/IPaymentProcessor.sol";

// @note Module is the BASE contract for all modules
/*   
        1. Each module has a unique identifier
        2. Used to trigger and receive callbacks and a modifier to authenticate the callers via module's proposal. trigger and recieve callback simply means -> communicate with the proposal contract
        3. Storage variables are the module's proposal and module's identifier. Does not change post initialization
*/
import {Module} from "src/modules/base/Module.sol";

// @note standard ERC20 token implementation from OZ
import {ERC20} from "@oz/token/ERC20/ERC20.sol";

// Interfaces
// @note standard ERC20 token interface from OZ
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// @note 1. executeTx
// 2. A really lengthy initialization function, involving owner, token, modules, authorizer, paymentProcessors and so on.
// 3. Rest all are external view functions
import {IProposal} from "src/proposal/IProposal.sol";

/**
 * @title Payment processor module implementation #2: Linear vesting curve.
 *
 * @dev The payment module handles the money flow to the contributors
 * (e.g. how many tokens are sent to which contributor at what time).
 *
 * @author byterocket
 */

// @note StreamingPaymentProcessor is module because the **module** contract is the base contract for all modules and StreamingPaymentProcessor is a module
// @note IPaymentProcessor cancels and fulfills payment orders based on a particular instance of a paymentClient
contract ConcurrentStreamingPaymentProcessor is Module, IPaymentProcessor {
    //--------------------------------------------------------------------------
    // Storage

    struct StreamingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _duration;
        uint _streamingWalletID //@audit-ok valid values will start from 1. 0 is not a valid streamingWalletID.
    }

    ////////////////////////////////
    // START ADDITIONAL CODE
    ////////////////////////////////

    mapping(address => mapping(address => bool)) public isActiveContributor;
    mapping(address => mapping(address => uint256)) public numContributorWallets;

    ////////////////////////////////
    // END ADDITIONAL CODE
    ////////////////////////////////

    ////////////////////////////////
    // START EDITED CODE
    ////////////////////////////////

    // paymentClient => contributor => streamingWalletID => Wallet
    mapping(address => mapping(address => mapping(uint256 => StreamingWallet))) private vestings;

    ////////////////////////////////
    // END EDITED CODE
    ////////////////////////////////

    // paymentClient => contributor => unclaimableAmount
    mapping(address => mapping(address => uint)) private unclaimableAmounts;

    ////////////////////////////////
    // START EDITED CODE
    ////////////////////////////////
    /// @notice list of addresses with open payment Orders per paymentClient
    mapping(address => address[]) private activePayments;

    /// @notice client => contributor => arrayOfWalletIdsWithPendingPayment
    mapping(address => mapping(address => uint256[])) private activeContributorPayments;
    ////////////////////////////////
    // END EDITED CODE
    ////////////////////////////////

    //--------------------------------------------------------------------------
    // Modifiers

    /// @notice checks that the caller is an active module
    modifier onlyModule() {
        if (!proposal().isModule(_msgSender())) {
            revert Module__PaymentManager__OnlyCallableByModule();
        }
        _;
    }

    /// @notice checks that the client is calling for itself
    modifier validClient(IPaymentClient client) {
        if (_msgSender() != address(client)) {
            revert Module__PaymentManager__CannotCallOnOtherClientsOrders();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // External Functions

    /// @inheritdoc Module
    function init(
        IProposal proposal_,
        Metadata memory metadata,
        bytes memory /*configdata*/
    ) external override(Module) initializer {
        __Module_init(proposal_, metadata); // @note This is fine, because one proposal can have
        // multiple modules but one module will only have one proposal attached to it.
    }

    /// @notice Release the releasable tokens.
    ///         In OZ VestingWallet this method is named release().
    function claimAll(IPaymentClient client) external {
        _claim(address(client), _msgSender());
    }

    // @todo add a function `claimFromSpecificId`
    function claimForSpecificWalletId(IPaymentClient client, uint256 walletId, bool retryForUnclaimableAmounts) external {
        if(!isActiveContributor[address(client)][_msgSender()] || (walletId > numContributorWallets[address(client)][_msgSender()])) {
            revert Module__PaymentManager__InvalidWallet();
        }

        if(_verifyActiveWalletId(walletId) == type(uint256).max) {
            revert Module__PaymentManager__InactiveWallet();
        }

        _claimForSpecificWalletId(address(client), _msgSender(), walletId, retryForUnclaimableAmounts);
    }

    /// @inheritdoc IPaymentProcessor
    function processPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        //We check if there are any new paymentOrders, without processing them
        if (client.paymentOrders().length > 0) {
            // @audit-ok
            // Ok, now, we do not want to over-write the payment orders and want to be able to create new ones.
            // Let's see how this goes
            
            // @audit-ok Remove the LOC that basically force-pays and therefore cancels all the pending open orders.
            // _cancelRunningOrders(client);

            // Collect outstanding orders and their total token amount.
            IPaymentClient.PaymentOrder[] memory orders;
            uint totalAmount;
            (orders, totalAmount) = client.collectPaymentOrders();

            if (token().balanceOf(address(client)) < totalAmount) {
                revert Module__PaymentManager__InsufficientTokenBalanceInClient();
            }
            
            // Generate Streaming Payments for all orders
            address _recipient;
            uint _amount;
            uint _start;
            uint _duration;
            uint _walletId;

            for (uint i; i < orders.length; i++) {
                _recipient = orders[i].recipient;
                _amount = orders[i].amount;
                _start = orders[i].createdAt;
                _duration = (orders[i].dueTo - _start);

                // @audit-ok we can't increase the value of numContributorWallets here, as it is possible that in the next
                // _addPayment step, this wallet is not actually added. So, we will increment the value of this mapping there only.
                // And for the same reason we cannot set the isActiveContributor mapping to true here.

                if(isActiveContributor[address(client)][_recipient]) {
                    _walletId = numContributorWallets[address(client)][_recipient] + 1;
                } else {
                    _walletId = 1;
                }

                _addPayment(
                    address(client), _recipient, _amount, _start, _duration, _walletId
                );

                emit PaymentOrderProcessed(
                    address(client), _recipient, _amount, _start, _duration
                );
            }
        }
    }

    /// @inheritdoc IPaymentProcessor
    function cancelRunningPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        _cancelRunningOrders(client);
    }

    /// @notice Deletes a contributors payment and leaves non-released tokens
    ///         in the PaymentClient.
    /// @param contributor Contributor's address.
    function removePayment(IPaymentClient client, address contributor)
        external
        onlyAuthorized
    {
        _removePayment(address(client), contributor);
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Getter for the start timestamp.
    /// @param contributor Contributor's address.
    function startForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor][walletId]._start;
    }

    /// @notice Getter for the vesting duration.
    /// @param contributor Contributor's address.
    function durationForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor][walletId]._duration;
    }

    /// @notice Getter for the amount of eth already released
    /// @param contributor Contributor's address.
    function releasedForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor][walletId]._released;
    }

    /// @notice Calculates the amount of tokens that has already vested.
    /// @param contributor Contributor's address.
    function vestedAmountForSpecificWalletId(address client, address contributor, uint timestamp, uint walletId)
        public
        view
        returns (uint)
    {
        return _vestingScheduleForSpecificWalletId(client, contributor, timestamp, walletId);
    }

    /// @notice Getter for the amount of releasable tokens.
    function releasableForSpecificWalletId(address client, address contributor, uint256 walletId)
        public
        view
        returns (uint)
    {
        // @audit unnecessary casting. block.timestamp returns uint256 by default
        return 
            vestedAmountForSpecificWalletId(client, contributor, uint(block.timestamp), walletId)
            - releasedForSpecificWalletId(client, contributor, walletId);
    }

    /// @notice Getter for the amount of tokens that could not be claimed.
    function unclaimable(address client, address contributor)
        public
        view
        returns (uint)
    {
        return unclaimableAmounts[client][contributor];
    }

    function token() public view returns (IERC20) {
        return this.proposal().token();
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    function findAddressInActivePayments(address client, address contributor)
        internal
        view
        returns (uint)
    {
        address[] memory contribSearchArray = activePayments[client];

        uint length = activePayments[client].length;
        // @audit-issue gas-opti
        for (uint i; i < length; i++) {
            if (contribSearchArray[i] == contributor) {
                return i;
            }
        }
        return type(uint).max;
    }

    function _verifyActiveWalletId(address client, address contributor, uint256 walletId) internal view returns(uint256) {
        uint256[] memory contributorWalletsArray = activeContributorPayments[client][contributor];
        uint256 contributorWalletsArrayLength = contributorsWalletArray.length;

        uint index;
        for(index; index < contributorWalletsArrayLength; ) {
            if(contributorWalletsArray[index] == walletId) {
                return index;
            }
            unchecked {
                ++index;
            }
        }

        return type(uint256).max;
    } 

    function _cancelRunningOrders(IPaymentClient client) internal {
        //IPaymentClient.PaymentOrder[] memory orders;
        //orders = client.paymentOrders();
        // @note _activePayments basically is the list of addresses of contributors that have pending payments
        address[] memory _activePayments = activePayments[address(client)];

        address _recipient;
        // @audit gas-opti
        for (uint i; i < _activePayments.length; ++i) {
            _recipient = _activePayments[i];

            _removePayment(address(client), _recipient);
        }
    }

    function _removePayment(address client, address contributor) internal {
        //we claim the earned funds for the contributor.
        _claim(client, contributor); //@note try to force pay the pending payment to the contributors

        //we remove the payment from the activePayments array
        uint contribIndex = findAddressInActivePayments(client, contributor);

        // @audit Shouldn't we first try and find the contributor in the activePayments array,
        // and only once we find it, then we should go ahead and call _claim, right? atleast would save a bit of gas.
        if (contribIndex != type(uint).max) {
            // Move the last element into the place to delete
            activePayments[client][contribIndex] =
                activePayments[client][activePayments[client].length - 1];
            // Remove the last element
            activePayments[client].pop();

            delete vestings[client][contributor];

            emit StreamingPaymentRemoved(client, contributor);
        }

        /// Note that all unvested funds remain in the PaymentClient, where they will be accounted for in future payment orders.
    }

    /// @notice Adds a new payment containing the details of the monetary flow
    ///         depending on the module.
    /// @param _contributor Contributor's address.
    /// @param _salary Salary contributor will receive per epoch.
    /// @param _start Start vesting timestamp.
    /// @param _duration Streaming duration timestamp.
    /// @param _walletId ID of the new wallet of the a particular contributor being added
    function _addPayment(
        address client,
        address _contributor,
        uint _salary,
        uint _start,
        uint _duration,
        uint _walletId
    ) internal {
        if (
            !validAddress(_contributor) || !validSalary(_salary) || !validStart(_start) || !validDuration(_duration)
        ) {
            emit InvalidStreamingOrderDiscarded ( _contributor, _salary, _start, _duration);
        } else {
            ++numContributorWallets[client][_contributor];

            if(_walletId == 1) {
                isActiveContributor[client][_contributor] = true;
                activePayments[client].push(_contributor); // @note If the walletId is not 1, then the contributor already exists.
            }

            vestings[client][_contributor][_walletId] =
                StreamingWallet(_salary, 0, _start, _duration);

            activePayments[client][_contributor].push(_walletId);

            emit StreamingPaymentAdded(
                client, _contributor, _salary, _start, _duration
            );
        }
    }

    function _claimAll(address client, address beneficiary) internal {
        uint amount = releasable(client, beneficiary);
        vestings[client][beneficiary]._released += amount;

        //if beneficiary has unclaimable tokens from before, add it to releasable amount
        if (unclaimableAmounts[client][beneficiary] > 0) {
            amount += unclaimable(client, beneficiary);
            delete unclaimableAmounts[client][beneficiary];
        }

        // we claim the earned funds for the contributor.
        address _token = address(token());
        (bool success, bytes memory data) = address(_token).call(
            abi.encodeWithSelector(
                IERC20(_token).transferFrom.selector,
                client,
                beneficiary,
                amount
            )
        );
        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            emit TokensReleased(beneficiary, _token, amount);
        } else {
            // if transfer fails, store amount to unclaimableAmounts.
            unclaimableAmounts[client][beneficiary] += amount;
        }
    }

    function _claimForSpecificWalletId(address client, address beneficiary, uint256 walletId, bool retryForUnclaimableAmounts) internal {
        uint amount = releasableForSpecificWalletId(client, beneficiary, walletId);
        vestings[client][beneficiary][walletId]._released += amount;

        if(retryForUnclaimableAmounts && unclaimableAmounts[client][beneficiary] > 0) {
            amount += unclaimable(client, beneficiary);
            delete unclaimableAmounts[client][beneficiary];
        }

        address _token = address(token());

        (bool success, bytes memory data) = _token.call(
            IERC20(_token).transferFrom.selector,
            client,
            beneficiary,
            amount
        );

        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            emit TokensReleased(beneficiary, _token, amount);
        } else {
            // if transfer fails, store amount to unclaimableAmounts.
            unclaimableAmounts[client][beneficiary] += amount;
        }

        // @todo decide whether you want to re-check the activeContributor and numWallets and activePayment array accounting here.
    }

    /// @notice Virtual implementation of the vesting formula.
    ///         Returns the amount vested, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param contributor The contributor to check on.
    /// @param timestamp Current block.timestamp
    /// @param walletId ID of a particular contributor's wallet whose vesting schedule needs to be checked
    function _vestingScheduleForSpecificWalletId(
        address client,
        address contributor,
        uint timestamp,
        uint walletId
    ) internal view virtual returns (uint) {
        uint totalAllocation = vestings[client][contributor][walletId]._salary;
        uint startContributor = startForSpecificWalletId(client, contributor, walletId);
        uint durationContributor = durationForSpecificWalletId(client, contributor, walletId);

        if (timestamp < startContributor) {
            return 0;
        } else if (timestamp >= startContributor + durationContributor) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - startContributor))
                / durationContributor;
        }
    }

    /// @notice validate address input.
    /// @param addr Address to validate.
    /// @return True if address is valid.
    function validAddress(address addr) internal view returns (bool) {
        if (
            addr == address(0) || addr == _msgSender() || addr == address(this)
                || addr == address(proposal())
        ) {
            return false;
        }
        return true;
    }

    function validSalary(uint _salary) internal pure returns (bool) {
        if (_salary == 0) {
            return false;
        }
        return true;
    }

    function validStart(uint _start) internal view returns (bool) {
        if (_start < block.timestamp || _start >= type(uint).max) {
            return false;
        }
        return true;
    }

    function validDuration(uint _duration) internal pure returns (bool) {
        // @audit gas-opti: return !(_duration == 0);
        if (_duration == 0) {
            return false;
        }
        return true;
    }
}

/**
I think one of the issues pointed out in the audit was the we were using both `msg.sender` and `_msgSender` 
interchangeably, right? And later this was fixed and we made `_msgSender` as our default. However, the `ElasticTokenReceipt` still uses `msg.sender`. Do we need to change that or let it be?

function `owner` and function `manager` are missing inline comments in `IProposal.sol`.

Most likely, the `@notice` comment for `event InvalidStreamingOrderDiscarded` in `StreamingPaymentProcessor` is not entirely accurate.

`StreamingPaymentProcessor._claim` uses the `transferFrom` function to transfer the proposal token from the PaymentClient to the contributor. Where is the approval from the `IPaymentClient` ?
 */

 // @note Payment order => PaymentProcessor processes them => Vesting payment is done over a period of time