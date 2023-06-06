// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.19;

import {IModule} from "src/modules/base/IModule.sol";

/**
 * @title Metadata Library
 *
 * @dev Provides common functions for {IModule}'s Metadata type.
 *
 * @author byterocket
 */
library LibMetadata {
    /// @dev Returns the identifier for given metadata.
    /// @param metadata The metadata.
    /// @return The metadata's identifier.
    function identifier(IModule.Metadata memory metadata)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                metadata.majorVersion, metadata.url, metadata.title
            )
        );
    }

    /// @dev Returns whether the given metadata is valid.
    /// @param metadata The metadata.
    /// @return True if metadata valid, false otherwise.
    function isValid(IModule.Metadata memory metadata)
        internal
        pure
        returns (bool)
    {
        // Invalid if url empty.
        if (bytes(metadata.url).length == 0) {
            return false;
        }

        // Invalid if title empty.
        if (bytes(metadata.title).length == 0) {
            return false;
        }

        // Invalid if version is v0.0.
        if (metadata.majorVersion == 0 && metadata.minorVersion == 0) {
            return false;
        }

        return true;
    }
}
