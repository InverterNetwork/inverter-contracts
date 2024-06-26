// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";

// Internal Interfaces
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Dependencies
import {ERC20Upgradeable} from "@oz-up/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC2771ContextUpgradeable,
    ContextUpgradeable
} from "@oz-up/metatx/ERC2771ContextUpgradeable.sol";
// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Bonding Curve Funding Manager Base Contract.
/// @author Inverter Network.
/// @notice This contract enables the base functionalities for issuing tokens along a bonding curve.
/// @dev The contract implements functionalties for:
///         - opening and closing the issuance of tokens.
///         - setting and subtracting of fees, expressed in BPS and subtracted from the collateral.
///         - calculating the issuance amount by means of an abstract function to be implemented in
///             the downstream contract.
abstract contract BondingCurveFundingManagerBase is
    IBondingCurveFundingManagerBase,
    IFundingManager,
    ERC20Upgradeable,
    Module
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Module)
        returns (bool)
    {
        return interfaceId == type(IBondingCurveFundingManagerBase).interfaceId
            || interfaceId == type(IFundingManager).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Stores the number of decimals used by the token.
    uint8 internal tokenDecimals;
    /// @dev Indicates whether the buy functionality is open or not.
    ///      Enabled = true || disabled = false.
    bool public buyIsOpen;
    /// @dev Buy fee expressed in base points, i.e. 0% = 0; 1% = 100; 10% = 1000
    uint public buyFee;
    /// @dev Base Points used for percentage calculation. This value represents 100%
    uint internal constant BPS = 10_000;
    /// @notice Accumulated trading fees collected from deposits made by users
    /// when engaging with the bonding curve-based funding manager.
    uint internal tradeFeeCollected;

    //--------------------------------------------------------------------------
    // Modifiers

    modifier buyingIsEnabled() {
        if (buyIsOpen == false) {
            revert BondingCurveFundingManager__BuyingFunctionaltiesClosed();
        }
        _;
    }

    /// @dev Modifier to guarantee token recipient is valid.
    modifier validReceiver(address _receiver) {
        if (_receiver == address(0) || _receiver == address(this)) {
            revert BondingCurveFundingManagerBase__InvalidRecipient();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @inheritdoc IBondingCurveFundingManagerBase
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        virtual
        buyingIsEnabled
        validReceiver(_receiver)
    {
        _buyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IBondingCurveFundingManagerBase
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        virtual
        buyingIsEnabled
    {
        _buyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IERC20Metadata
    function decimals()
        public
        view
        override(ERC20Upgradeable)
        returns (uint8)
    {
        return tokenDecimals;
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Functions

    /// @inheritdoc IBondingCurveFundingManagerBase
    function openBuy() external onlyOrchestratorOwner {
        _openBuy();
    }

    /// @inheritdoc IBondingCurveFundingManagerBase
    function closeBuy() external onlyOrchestratorOwner {
        _closeBuy();
    }

    /// @inheritdoc IBondingCurveFundingManagerBase
    function setBuyFee(uint _fee) external onlyOrchestratorOwner {
        _setBuyFee(_fee);
    }

    //--------------------------------------------------------------------------
    // Public Functions Implemented in Downstream Contract

    /// @inheritdoc IBondingCurveFundingManagerBase
    function getStaticPriceForBuying() external virtual returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Function used for wrapping the call to the external contract responsible for
    /// calculating the issuing amount. This function is an abstract function and must be
    /// implemented in the downstream contract.
    /// @param _depositAmount The amount of collateral token that is deposited
    /// @return uint Return the amount of tokens to be issued
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        virtual
        returns (uint);

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Internal function to handle the buying of tokens.
    /// This function performs the core logic for buying tokens. It transfers the collateral,
    /// deducts any applicable fees, and mints new tokens for the buyer.
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral to deposit for buying tokens.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @return mintAmount The amount of issuance token minted to the receiver address
    /// @return feeAmount The amount of collateral token subtracted as fee
    function _buyOrder(
        address _receiver,
        uint _depositAmount,
        uint _minAmountOut
    ) internal returns (uint mintAmount, uint feeAmount) {
        if (_depositAmount == 0) {
            revert BondingCurveFundingManager__InvalidDepositAmount();
        }
        // Transfer collateral, confirming that correct amount == allowance
        __Module_orchestrator.fundingManager().token().safeTransferFrom(
            _msgSender(), address(this), _depositAmount
        );
        if (buyFee > 0) {
            // Calculate fee amount and deposit amount subtracted by fee
            (_depositAmount, feeAmount) =
                _calculateNetAmountAndFee(_depositAmount, buyFee);
            // Add fee amount to total collected fee
            tradeFeeCollected += feeAmount;
        }
        // Calculate mint amount based on upstream formula
        mintAmount = _issueTokensFormulaWrapper(_depositAmount);
        // Revert when the mint amount is lower than minimum amount the user expects
        if (mintAmount < _minAmountOut) {
            revert BondingCurveFundingManagerBase__InsufficientOutputAmount();
        }
        // Mint tokens to address
        _mint(_receiver, mintAmount);
        // Emit event
        emit TokensBought(_receiver, _depositAmount, mintAmount, _msgSender());
    }

    /// @dev Opens the buy functionality by setting the state variable `buyIsOpen` to true.
    function _openBuy() internal {
        if (buyIsOpen == true) {
            revert BondingCurveFundingManager__BuyingAlreadyOpen();
        }
        buyIsOpen = true;
        emit BuyingEnabled();
    }

    /// @dev Closes the buy functionality by setting the state variable `buyIsOpen` to false.
    function _closeBuy() internal {
        if (buyIsOpen == false) {
            revert BondingCurveFundingManager__BuyingAlreadyClosed();
        }
        buyIsOpen = false;
        emit BuyingDisabled();
    }

    /// @dev Sets the buy transaction fee, expressed in BPS.
    /// @param _fee The fee percentage to set for buy transactions.
    function _setBuyFee(uint _fee) internal {
        if (_fee >= BPS) {
            revert BondingCurveFundingManager__InvalidFeePercentage();
        }
        emit BuyFeeUpdated(_fee, buyFee);
        buyFee = _fee;
    }

    /// @dev Calculates the net amount after fee deduction and the fee amount based on
    /// a transaction amount and a specified fee percentage.
    /// @param _transactionAmount The amount involved in the transaction before fee deduction.
    /// @param _feePct The fee percentage to be deducted, represented in basis points (BPS).
    /// @return netAmount The transaction amount after fee deduction.
    /// @return feeAmount The amount of fee deducted from the transaction amount.
    function _calculateNetAmountAndFee(uint _transactionAmount, uint _feePct)
        internal
        pure
        returns (uint netAmount, uint feeAmount)
    {
        // Calculate fee amount
        feeAmount = (_transactionAmount * _feePct) / BPS;
        // Calculate net amount after fee deduction
        netAmount = _transactionAmount - feeAmount;
    }

    /// @dev Sets the number of decimals for the token.
    /// This function updates the `tokenDecimals` state variable and should be be overriden by
    /// the implementation contract if input validation is needed.
    /// @param _decimals The number of decimals to set for the token.
    function _setTokenDecimals(uint8 _decimals) internal virtual {
        uint8 oldDecimals = tokenDecimals;
        tokenDecimals = _decimals;
        emit TokenDecimalsUpdated(oldDecimals, tokenDecimals);
    }

    //--------------------------------------------------------------------------
    // OnlyOrchestrator Mutating Functions

    /// @inheritdoc IFundingManager
    function transferOrchestratorToken(address to, uint amount)
        external
        onlyOrchestrator
    {
        __Module_orchestrator.fundingManager().token().safeTransfer(to, amount);

        emit TransferOrchestratorToken(to, amount);
    }

    //--------------------------------------------------------------------------
    // ERC2771 Context Upgradeable

    /// Needs to be overriden, because they are imported via the ERC20Upgradeable as well
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return super._msgSender();
    }

    /// Needs to be overriden, because they are imported via the ERC20Upgradeable as well
    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return super._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
