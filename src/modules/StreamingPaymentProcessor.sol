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
contract StreamingPaymentProcessor is Module, IPaymentProcessor {
    //--------------------------------------------------------------------------
    // Storage

    struct StreamingWallet {
        uint _salary;
        uint _released;
        uint _start;
        uint _duration;
    }

    // paymentClient => contributor => Payment
    mapping(address => mapping(address => StreamingWallet)) private vestings;
    // paymentClient => contributor => unclaimableAmount
    mapping(address => mapping(address => uint)) private unclaimableAmounts;

    /// @notice list of addresses with open payment Orders per paymentClient
    // @note for one particular paymentClient, which addresses have pending payment orders
    mapping(address => address[]) private activePayments;

    //--------------------------------------------------------------------------
    // Events

    /// @notice Emitted when a payment gets processed for execution.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param duration Timestamp at which the full amount should be claimable.
    event StreamingPaymentAdded(
        address indexed paymentClient,
        address indexed recipient,
        uint amount,
        uint start,
        uint duration
    );

    /// @notice Emitted when the vesting to an address is removed.
    /// @param recipient The address that will stop receiving payment.
    event StreamingPaymentRemoved(
        address indexed paymentClient, address indexed recipient
    );

    /// @notice Emitted when a running vesting schedule gets updated.
    /// @param recipient The address that will receive the payment.
    /// @param newSalary The new amount of tokens the payment consists of.
    /// @param newDuration Number of blocks over which the amount will vest.
    event PaymentUpdated(address recipient, uint newSalary, uint newDuration);

    /// @notice Emitted when a running vesting schedule gets updated.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    /// @param start Timestamp at which the vesting starts.
    /// @param duration Number of blocks over which the amount will vest
    event InvalidStreamingOrderDiscarded(
        address indexed recipient, uint amount, uint start, uint duration
    );

    //--------------------------------------------------------------------------
    // Errors

    /// @notice insufficient tokens in the client to do payments
    error Module__PaymentManager__InsufficientTokenBalanceInClient();

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
    function claim(IPaymentClient client) external {
        _claim(address(client), _msgSender());
    }

    /// @inheritdoc IPaymentProcessor
    function processPayments(IPaymentClient client)
        external
        onlyModule
        validClient(client)
    {
        //We check if there are any new paymentOrders, without processing them
        if (client.paymentOrders().length > 0) { // @note returns the list of outstanding payment orders.
            // If there are, we remove all payments that would be overwritten
            // Doing it at the start ensures that collectPaymentOrders will always start from a blank slate concerning balances/allowances.
            // @note cancel will try and force-pay the pending payments to the contributors.
            _cancelRunningOrders(client);

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
            // @audit gas-opti
            for (uint i; i < orders.length; i++) {
                _recipient = orders[i].recipient;
                _amount = orders[i].amount;
                _start = orders[i].createdAt;
                _duration = (orders[i].dueTo - _start);

                _addPayment(
                    address(client), _recipient, _amount, _start, _duration
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

    // @follow-up why discrepancy between who can call cancelRunningPayments and who can call removePayment

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
    function start(address client, address contributor)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor]._start;
    }

    /// @notice Getter for the vesting duration.
    /// @param contributor Contributor's address.
    function duration(address client, address contributor)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor]._duration;
    }

    /// @notice Getter for the amount of eth already released // @audit does it have to be ETH necessarily?
    /// @param contributor Contributor's address.
    function released(address client, address contributor)
        public
        view
        returns (uint)
    {
        return vestings[client][contributor]._released;
    }

    /// @notice Calculates the amount of tokens that has already vested.
    /// @param contributor Contributor's address.
    function vestedAmount(address client, address contributor, uint timestamp)
        public
        view
        returns (uint)
    {
        return _vestingSchedule(client, contributor, timestamp);
    }

    /// @notice Getter for the amount of releasable tokens.
    function releasable(address client, address contributor)
        public
        view
        returns (uint)
    {
        // @audit unnecessary casting. block.timestamp returns uint256 by default
        return vestedAmount(client, contributor, uint(block.timestamp))
            - released(client, contributor);
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

    // @audit if internal function, why underscore not used?
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
    function _addPayment(
        address client,
        address _contributor,
        uint _salary,
        uint _start,
        uint _duration
    ) internal {
        if (
            !validAddress(_contributor) || !validSalary(_salary)
                || !validStart(_start) || !validDuration(_duration)
        ) {
            emit InvalidStreamingOrderDiscarded(
                _contributor, _salary, _start, _duration
            );
        } 
        // @follow-up else statment isn't really wrong. but why have we used it?
        else {
            vestings[client][_contributor] =
                StreamingWallet(_salary, 0, _start, _duration);

            uint contribIndex =
                findAddressInActivePayments(client, _contributor);
            if (contribIndex == type(uint).max) {
                activePayments[client].push(_contributor);
            } // @audit why is the else statement not included?

            // This event would be emitted even if the contributor isn't necessarily added. Fix?
            emit StreamingPaymentAdded(
                client, _contributor, _salary, _start, _duration
            );
        }
    }

    function _claim(address client, address beneficiary) internal {
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
        // @audit-issue the `call` will return true for any EOA address and also for address(0).
        // @audit-issue So a better approach would be to check the before and after balance of the token for the beneficiary
        // @audit-issue The data returned by _token can be so large, that it results in a DOS attack/consistent OOG
        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            emit TokensReleased(beneficiary, _token, amount);
        } else {
            // if transfer fails, store amount to unclaimableAmounts.
            unclaimableAmounts[client][beneficiary] += amount;
        }
    }

    /// @notice Virtual implementation of the vesting formula.
    ///         Returns the amount vested, as a function of time,
    ///         for an asset given its total historical allocation.
    /// @param contributor The contributor to check on.
    /// @param timestamp Current block.timestamp
    function _vestingSchedule(
        address client,
        address contributor,
        uint timestamp
    ) internal view virtual returns (uint) {
        uint totalAllocation = vestings[client][contributor]._salary;
        uint startContributor = start(client, contributor);
        uint durationContributor = duration(client, contributor);

        if (timestamp < startContributor) {
            return 0;
        } else if (timestamp > startContributor + durationContributor) { // @audit we can make this >= ,right?
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