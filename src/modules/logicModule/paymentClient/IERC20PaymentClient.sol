// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IPaymentProcessor} from
    "src/modules/paymentProcessor/IPaymentProcessor.sol";

interface IERC20PaymentClient {
    struct PaymentOrder {
        /// @dev The recipient of the payment.
        address recipient;
        /// @dev The amount of tokens to pay.
        uint amount;
        /// @dev Timestamp at which the order got created.
        uint createdAt;
        /// @dev Timestamp at which the payment SHOULD be fulfilled.
        uint dueTo;
    }

    //--------------------------------------------------------------------------
    // Errors

    /// @notice Function is only callable by authorized address.
    error Module__ERC20PaymentClient__CallerNotAuthorized();

    /// @notice ERC20 token transfer failed.
    error Module__ERC20PaymentClient__TokenTransferFailed();

    /// @notice Given recipient invalid.
    error Module__ERC20PaymentClient__InvalidRecipient();

    /// @notice Given amount invalid.
    error Module__ERC20PaymentClient__InvalidAmount();

    /// @notice Given dueTo invalid.
    error Module__ERC20PaymentClient__InvalidDueTo();

    /// @notice Given arrays' length mismatch.
    error Module__ERC20PaymentClient__ArrayLengthMismatch();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Added a payment order.
    /// @param recipient The address that will receive the payment.
    /// @param amount The amount of tokens the payment consists of.
    event PaymentOrderAdded(address indexed recipient, uint amount);

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the list of outstanding payment orders.
    /// @return paymentOrders List of outstanding payment orders.
    /// @custom:tags amount:decimal
    function paymentOrders() external view returns (PaymentOrder[] memory);

    /// @notice Returns the total outstanding token payment amount.
    /// @return outstandingTokenAmount Total outstanding token payment amount.
    /// @custom:tags outstandingTokenAmount:decimal
    function outstandingTokenAmount() external view returns (uint);

    /// @notice Collects outstanding payment orders.
    /// @dev Marks the orders as completed for the client.
    ///      The responsibility to fulfill the orders are now in the caller's
    ///      hand!
    /// @return paymentOrders list of payment orders
    /// @return outstandingTokenAmount total amount of token to pay
    /// @custom:tags amount:decimal outstandingTokenAmount:decimal
    function collectPaymentOrders()
        external
        returns (PaymentOrder[] memory, uint);

    /// @notice Notifies the PaymentClient, that tokens have been paid out accordingly
    /// @dev Payment Client will reduce the total amount of tokens it will stock up by the given amount
    /// This has to be called by a paymentProcessor
    /// @param amount amount of tokens that have been paid out
    /// @custom:tags amount:decimal
    function amountPaid(uint amount) external;
}
