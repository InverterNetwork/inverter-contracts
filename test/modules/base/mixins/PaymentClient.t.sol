// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// SuT
import {
    ERC20PaymentClientMock,
    IERC20PaymentClient
} from "test/utils/mocks/modules/mixins/ERC20PaymentClientMock.sol";

// Mocks
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";

contract ERC20PaymentClientTest is Test {
    // SuT
    ERC20PaymentClientMock ERC20PaymentClient;

    // Mocks
    ERC20Mock token;

    function setUp() public {
        token = new ERC20Mock("Mock", "MOCK");

        ERC20PaymentClient = new ERC20PaymentClientMock(token);
        ERC20PaymentClient.setIsAuthorized(address(this), true);
    }

    //----------------------------------
    // Test: addPaymentOrder()

    function testAddPaymentOrder(
        uint orderAmount,
        address recipient,
        uint amount,
        uint dueTo
    ) public {
        // Note to stay reasonable.
        orderAmount = bound(orderAmount, 0, 10);

        _assumeValidRecipient(recipient);
        _assumeValidAmount(amount);

        // Sum of all token amounts should not overflow.
        uint sum;
        for (uint i; i < orderAmount; ++i) {
            unchecked {
                sum += amount;
            }
            vm.assume(sum > amount);
        }

        for (uint i; i < orderAmount; ++i) {
            ERC20PaymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }

        IERC20PaymentClient.PaymentOrder[] memory orders =
            ERC20PaymentClient.paymentOrders();

        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            assertEq(orders[i].dueTo, dueTo);
        }

        assertEq(ERC20PaymentClient.outstandingTokenAmount(), amount * orderAmount);
    }

    function testAddPaymentOrderFailsForInvalidRecipient() public {
        address[] memory invalids = _createInvalidRecipients();
        uint amount = 1e18;
        uint dueTo = block.timestamp;

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IERC20PaymentClient.Module__ERC20PaymentClient__InvalidRecipient.selector
            );
            ERC20PaymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: invalids[0],
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }
    }

    function testAddPaymentOrderFailsForInvalidAmount() public {
        address recipient = address(0xCAFE);
        uint[] memory invalids = _createInvalidAmounts();
        uint dueTo = block.timestamp;

        for (uint i; i < invalids.length; ++i) {
            vm.expectRevert(
                IERC20PaymentClient.Module__ERC20PaymentClient__InvalidAmount.selector
            );
            ERC20PaymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: recipient,
                    amount: invalids[0],
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }
    }

    //----------------------------------
    // Test: addPaymentOrders()

    function testAddPaymentOrders() public {
        IERC20PaymentClient.PaymentOrder[] memory ordersToAdd =
            new IERC20PaymentClient.PaymentOrder[](3);
        ordersToAdd[0] = IERC20PaymentClient.PaymentOrder({
            recipient: address(0xCAFE1),
            amount: 100e18,
            createdAt: block.timestamp,
            dueTo: block.timestamp
        });
        ordersToAdd[1] = IERC20PaymentClient.PaymentOrder({
            recipient: address(0xCAFE2),
            amount: 100e18,
            createdAt: block.timestamp,
            dueTo: block.timestamp + 1
        });
        ordersToAdd[2] = IERC20PaymentClient.PaymentOrder({
            recipient: address(0xCAFE3),
            amount: 100e18,
            createdAt: block.timestamp,
            dueTo: block.timestamp + 2
        });

        ERC20PaymentClient.addPaymentOrders(ordersToAdd);

        IERC20PaymentClient.PaymentOrder[] memory orders =
            ERC20PaymentClient.paymentOrders();

        assertEq(orders.length, 3);
        for (uint i; i < 3; ++i) {
            assertEq(orders[i].recipient, ordersToAdd[i].recipient);
            assertEq(orders[i].amount, ordersToAdd[i].amount);
            assertEq(orders[i].dueTo, ordersToAdd[i].dueTo);
        }

        assertEq(ERC20PaymentClient.outstandingTokenAmount(), 300e18);
    }

    //----------------------------------
    // Test: collectPaymentOrders()

    function testCollectPaymentOrders(
        uint orderAmount,
        address recipient,
        uint amount,
        uint dueTo
    ) public {
        // Note to stay reasonable.
        orderAmount = bound(orderAmount, 0, 10);

        _assumeValidRecipient(recipient);
        _assumeValidAmount(amount);

        // Sum of all token amounts should not overflow.
        uint sum;
        for (uint i; i < orderAmount; ++i) {
            unchecked {
                sum += amount;
            }
            vm.assume(sum > amount);
        }

        for (uint i; i < orderAmount; ++i) {
            ERC20PaymentClient.addPaymentOrder(
                IERC20PaymentClient.PaymentOrder({
                    recipient: recipient,
                    amount: amount,
                    createdAt: block.timestamp,
                    dueTo: dueTo
                })
            );
        }

        IERC20PaymentClient.PaymentOrder[] memory orders;
        uint totalOutstandingAmount;
        (orders, totalOutstandingAmount) = ERC20PaymentClient.collectPaymentOrders();

        // Check that orders are correct.
        assertEq(orders.length, orderAmount);
        for (uint i; i < orderAmount; ++i) {
            assertEq(orders[i].recipient, recipient);
            assertEq(orders[i].amount, amount);
            assertEq(orders[i].dueTo, dueTo);
        }

        // Check that total outstanding token amount is correct.
        assertEq(totalOutstandingAmount, orderAmount * amount);

        // Check that orders in ERC20PaymentClient got reset.
        IERC20PaymentClient.PaymentOrder[] memory updatedOrders;
        updatedOrders = ERC20PaymentClient.paymentOrders();
        assertEq(updatedOrders.length, 0);

        // Check that outstanding token amount in ERC20PaymentClient got reset.
        assertEq(ERC20PaymentClient.outstandingTokenAmount(), 0);

        // Check that we received allowance to fetch tokens from ERC20PaymentClient.
        assertTrue(
            token.allowance(address(ERC20PaymentClient), address(this))
                >= totalOutstandingAmount
        );
    }

    function testCollectPaymentOrdersFailsCallerNotAuthorized() public {
        ERC20PaymentClient.setIsAuthorized(address(this), false);

        vm.expectRevert(
            IERC20PaymentClient.Module__ERC20PaymentClient__CallerNotAuthorized.selector
        );
        ERC20PaymentClient.collectPaymentOrders();
    }

    //--------------------------------------------------------------------------
    // Assume Helper Functions

    function _assumeValidRecipient(address recipient) internal view {
        address[] memory invalids = _createInvalidRecipients();
        for (uint i; i < invalids.length; ++i) {
            vm.assume(recipient != invalids[i]);
        }
    }

    function _assumeValidAmount(uint amount) internal pure {
        uint[] memory invalids = _createInvalidAmounts();
        for (uint i; i < invalids.length; ++i) {
            vm.assume(amount != invalids[i]);
        }
    }

    //--------------------------------------------------------------------------
    // Data Creation Helper Functions

    /// @dev Returns all invalid recipients.
    function _createInvalidRecipients()
        internal
        view
        returns (address[] memory)
    {
        address[] memory invalids = new address[](2);

        invalids[0] = address(0);
        invalids[1] = address(ERC20PaymentClient);

        return invalids;
    }

    /// @dev Returns all invalid amounts.
    function _createInvalidAmounts() internal pure returns (uint[] memory) {
        uint[] memory invalids = new uint[](1);

        invalids[0] = 0;

        return invalids;
    }
}
