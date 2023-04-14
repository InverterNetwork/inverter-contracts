// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ElasticReceiptTokenBase} from
    "src/proposal/token/ElasticReceiptTokenBase.sol";

abstract contract ElasticReceiptTokenUpgradeable is ElasticReceiptTokenBase {
    //--------------------------------------------------------------------------
    // Initialization

    /// @dev Initializes the contract.
    /// @dev Reinitialization possible as long as no tokens minted.
    function __ElasticReceiptToken_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal {
        require(_totalTokenSupply == 0);

        // Set IERC20Metadata.
        name = name_;
        symbol = symbol_;
        decimals = decimals_;

        // Total supply of bits are 'pre-mined' to zero address.
        //
        // During mint, bits are transferred from the zero address and
        // during burn, bits are transferred to the zero address.
        _accountBits[address(0)] = TOTAL_BITS;
    }
}
