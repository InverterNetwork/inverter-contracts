// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {BondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";
// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Redeeming Bonding Curve Funding Manager Base Contract.
/// @author Inverter Network.
/// @notice This contract enables the base functionalities for redeeming issued tokens for collateral
/// tokens along a bonding curve.
/// @dev The contract implements functionalties for:
///         - opening and closing the redeeming of collateral tokens.
///         - setting and subtracting of fees, expressed in BPS and subtracted from the collateral.
///         - calculating the redeeming amount by means of an abstract function to be implemented in
///             the downstream contract.
abstract contract RedeemingBondingCurveFundingManagerBase is
    IRedeemingBondingCurveFundingManagerBase,
    BondingCurveFundingManagerBase
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BondingCurveFundingManagerBase)
        returns (bool)
    {
        return interfaceId
            == type(IRedeemingBondingCurveFundingManagerBase).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Indicates whether the sell functionality is open or not.
    ///      Enabled = true || disabled = false.
    bool public sellIsOpen;
    /// @dev Sell fee expressed in base points, i.e. 0% = 0; 1% = 100; 10% = 1000
    uint public sellFee;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier sellingIsEnabled() {
        if (sellIsOpen == false) {
            revert
                RedeemingBondingCurveFundingManager__SellingFunctionaltiesClosed();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
        validReceiver(_receiver)
    {
        _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        virtual
        sellingIsEnabled
    {
        _sellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function openSell() external onlyOrchestratorOwner {
        _openSell();
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function closeSell() external onlyOrchestratorOwner {
        _closeSell();
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function setSellFee(uint _fee) external onlyOrchestratorOwner {
        _setSellFee(_fee);
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function getStaticPriceForSelling() external virtual returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Function used for wrapping the call to the external contract responsible for
    /// calculating the redeeming amount. This function is an abstract function and must be
    /// implemented in the downstream contract.
    /// @param _depositAmount The amount of issuing token that is deposited
    /// @return uint Return the amount of collateral to be redeemed
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Executes a sell order by transferring tokens from the receiver to the contract,
    /// calculating the redeem amount, and finally transferring the redeem amount back to the receiver.
    /// This function is internal and not intended for end-user interaction.
    /// PLEASE NOTE:
    /// The current implementation only requires that enough collateral token is held for redeeming
    /// to be possible. No further functionality is implemented which would manages the outflow of
    /// collateral, e.g., restricting max redeemable amount per user, or a redeemable amount which
    /// differes from the actual balance.
    /// Throws an exception if `_depositAmount` is zero or if there's insufficient collateral in the
    /// contract for redemption.
    /// @param _receiver The address receiving the redeem amount.
    /// @param _depositAmount The amount of tokens being sold by the receiver.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @return redeemAmount The amount of tokens that are transfered to the receiver in exchange for _depositAmount.
    /// @return feeAmount The amount of collateral token subtracted as fee
    function _sellOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    ) internal returns (uint redeemAmount, uint feeAmount) {
        if (_depositAmount == 0) {
            revert RedeemingBondingCurveFundingManager__InvalidDepositAmount();
        }
        // Calculate redeem amount based on upstream formula
        redeemAmount = _redeemTokensFormulaWrapper(_depositAmount);

        // Burn issued token from user
        _burn(_msgSender(), _depositAmount);

        if (sellFee > 0) {
            // Calculate fee amount and redeem amount subtracted by fee
            (redeemAmount, feeAmount) =
                _calculateNetAmountAndFee(redeemAmount, sellFee);
            // Add fee amount to total collected fee
            tradeFeeCollected += feeAmount;
        }
        // Revert when the redeem amount is lower than minimum amount the user expects
        if (redeemAmount < _minAmountOut) {
            revert RedeemingBondingCurveFundingManager__InsufficientOutputAmount(
            );
        }
        // Require that enough collateral token is held to be redeemable
        if (
            redeemAmount
                > __Module_orchestrator.fundingManager().token().balanceOf(
                    address(this)
                )
        ) {
            revert
                RedeemingBondingCurveFundingManager__InsufficientCollateralForRedemption(
            );
        }
        // Transfer tokens to receiver
        __Module_orchestrator.fundingManager().token().transfer(
            _receiver, redeemAmount
        );
        // Emit event
        emit TokensSold(_receiver, _depositAmount, redeemAmount, _msgSender());
    }

    /// @dev Opens the sell functionality by setting the state variable `sellIsOpen` to true.
    function _openSell() internal {
        if (sellIsOpen == true) {
            revert RedeemingBondingCurveFundingManager__SellingAlreadyOpen();
        }
        sellIsOpen = true;
        emit SellingEnabled();
    }

    /// @dev Closes the sell functionality by setting the state variable `sellIsOpen` to false.
    function _closeSell() internal {
        if (sellIsOpen == false) {
            revert RedeemingBondingCurveFundingManager__SellingAlreadyClosed();
        }
        sellIsOpen = false;
        emit SellingDisabled();
    }

    /// @dev Sets the sell transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for sell transactions.
    function _setSellFee(uint _fee) internal {
        if (_fee > BPS) {
            revert RedeemingBondingCurveFundingManager__InvalidFeePercentage();
        }
        emit SellFeeUpdated(_fee, sellFee);
        sellFee = _fee;
    }
}
