// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @notice Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @notice Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     * @dev Note that `value` may be zero.
     *
     * @param value The transfered amount tags:[value:decimals]
     */
    event Transfer(address indexed from, address indexed to, uint value);

    /**
     * @notice Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     *
     * @param value The approved amount tags:[value:decimals]
     */
    event Approval(address indexed owner, address indexed spender, uint value);

    /**
     * @notice Returns the value of tokens in existence.
     *
     * @return totalSupply The total supply of tokens. tags:[totalSupply:decimals]
     */
    function totalSupply() external view returns (uint);

    /**
     * @notice Returns the value of tokens owned by `account`.
     *
     * @return value The balance of the account. tags:[value:decimals]
     */
    function balanceOf(address account) external view returns (uint);

    /**
     * @notice Moves a `value` amount of tokens from the caller's account to `to`.
     * @dev Emits a {Transfer} event.
     *
     * @return boolean A boolean value indicating whether the operation succeeded.
     */
    function transfer(address to, uint value) external returns (bool);

    /**
     * @notice Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     * @dev This value changes when {approve} or {transferFrom} are called.
     *
     * @return allowance The allowance of the owner. tags:[allowance:decimals]
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint);

    /**
     * @notice Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * @dev Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     *
     * @param value Amount of tokens to be granted allowance tags:[value:decimals]
     */
    function approve(address spender, uint value) external returns (bool);

    /**
     * @notice Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * @dev Emits a {Transfer} event.
     *
     * @param value The amaount of tokens to be transfered tags:[value:decimals]
     *
     * @return boolean A boolean value indicating whether the operation succeeded.
     */
    function transferFrom(address from, address to, uint value)
        external
        returns (bool);
}
