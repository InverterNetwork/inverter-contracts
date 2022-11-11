// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.13;

import {IPaymentProcessor} from "src/modules/IPaymentProcessor.sol";
import {IPaymentClient} from "src/modules/mixins/IPaymentClient.sol";

contract PaymentProcessorMock is IPaymentProcessor {
    //--------------------------------------------------------------------------
    // IPaymentProcessor Functions

    function processPayments(IPaymentClient client)
        external
    {}
}
