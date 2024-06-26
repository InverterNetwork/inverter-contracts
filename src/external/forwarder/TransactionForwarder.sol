// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Interfaces
import {ITransactionForwarder} from
    "src/external/forwarder/ITransactionForwarder.sol";

// External Dependencies
import {ERC2771Forwarder} from "@oz/metatx/ERC2771Forwarder.sol";
import {ERC2771Context} from "@oz/metatx/ERC2771Context.sol";

import {Context} from "@oz/utils/Context.sol";

contract TransactionForwarder is
    ITransactionForwarder,
    ERC2771Forwarder,
    Context
{
    //--------------------------------------------------------------------------
    // Initialization

    // Constructor
    constructor(string memory name) ERC2771Forwarder(name) {}

    //--------------------------------------------------------------------------
    // Multicall Functions

    /// @inheritdoc ITransactionForwarder
    function executeMulticall(SingleCall[] calldata calls)
        external
        returns (Result[] memory results)
    {
        uint length = calls.length;
        results = new Result[](length);

        SingleCall calldata calli;
        bytes memory data;

        //run through all of the calls
        for (uint i = 0; i < length; i++) {
            calli = calls[i];
            //Check if the target actually trusts the forwarder
            if (!__isTrustedByTarget(calli.target)) {
                revert ERC2771UntrustfulTarget(calli.target, address(this));
            }

            //Add call target to the end of the calldata
            //This will be read by the ERC2771Context of the target contract
            data = abi.encodePacked(calli.callData, _msgSender());

            //Do the call
            (bool success, bytes memory returnData) = calli.target.call(data);

            //In case call fails check if it its allowed to fail
            if (!success && !calli.allowFailure) {
                revert CallFailed(calli);
            }

            //set result correctly
            results[i] = Result(success, returnData);
        }
    }

    // Copied from the ERC2771Forwarder as it isnt declared internal ಠ_ಠ
    // Just added a _ because i cant override it
    /**
     * @dev Returns whether the target trusts this forwarder.
     *
     * This function performs a static call to the target contract calling the
     * {ERC2771Context-isTrustedForwarder} function.
     */
    function __isTrustedByTarget(address target) private view returns (bool) {
        bytes memory encodedParams =
            abi.encodeCall(ERC2771Context.isTrustedForwarder, (address(this)));

        bool success;
        uint returnSize;
        uint returnValue;
        /// @solidity memory-safe-assembly
        assembly {
            // Perform the staticcal and save the result in the scratch space.
            // | Location  | Content  | Content (Hex)                                                      |
            // |-----------|----------|--------------------------------------------------------------------|
            // |           |          |                                                           result ↓ |
            // | 0x00:0x1F | selector | 0x0000000000000000000000000000000000000000000000000000000000000001 |
            success :=
                staticcall(
                    gas(),
                    target,
                    add(encodedParams, 0x20),
                    mload(encodedParams),
                    0,
                    0x20
                )
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        return success && returnSize >= 0x20 && returnValue > 0;
    }
}
