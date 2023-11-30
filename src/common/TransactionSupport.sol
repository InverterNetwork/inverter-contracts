// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {ERC2771ContextUpgradeable} from
    "@oz-up/metatx/ERC2771ContextUpgradeable.sol";

abstract contract TransactionSupport is ERC2771ContextUpgradeable {
    address public multicall;

    constructor(address _trustedForwarder)
        ERC2771ContextUpgradeable(_trustedForwarder)
    {}

    function setMulticallContract(address _multicall) public {
        multicall = _multicall;
    }

    function _msgSender()
        internal
        view
        virtual
        override
        returns (address sender)
    {
        if (msg.sender == multicall) {
            /// @solidity memory-safe-assembly
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return super._msgSender();
        }
    }
}
