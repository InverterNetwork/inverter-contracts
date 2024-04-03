// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)
pragma solidity ^0.8.0;

import "./IERC20.sol";

/**
 * @notice Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 *
 * @author OpenZeppelin
 */
interface IERC20Metadata is IERC20 {
    /**
     * @notice Returns the name of the token.
     *
     * @return name The name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the symbol of the token.
     *
     * @return symbol The symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the decimals places of the token.
     *
     * @return decimals The decimals of the token.
     */
    function decimals() external view returns (uint8);
}
