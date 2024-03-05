// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

// Internal Dependencies
import {Module} from "src/modules/base/Module.sol";
import {RedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/RedeemingBondingCurveFundingManagerBase.sol";
import {BondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/BondingCurveFundingManagerBase.sol";
import {FixedPointMathLib} from "./formula/FixedPointMathLib.sol";

// Internal Interfaces
import {IBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IBondingCurveFundingManagerBase.sol";
import {IRedeemingBondingCurveFundingManagerBase} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRedeemingBondingCurveFundingManagerBase.sol";
import {IToposBondingCurveFundingManager} from
    "src/modules/fundingManager/bondingCurveFundingManager/IToposBondingCurveFundingManager.sol";
import {IRepayer} from
    "src/modules/fundingManager/bondingCurveFundingManager/IRepayer.sol";
import {ILiquidityPool} from
    "src/modules/logicModule/liquidityPool/ILiquidityPool.sol";
import {IOrchestrator} from "src/orchestrator/IOrchestrator.sol";
import {IFundingManager} from "src/modules/fundingManager/IFundingManager.sol";
import {IToposFormula} from "./formula/IToposFormula.sol";
import {IAuthorizer} from "src/modules/authorizer/IAuthorizer.sol";

// External Interfaces
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@oz/token/ERC20/extensions/IERC20Metadata.sol";

// External Libraries
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

/// @title Topos Bonding Curve Funding Manager Contract.
/// @author Inverter Network.
/// @notice This contract enables the issuance and redeeming of tokens on a bonding curve
/// @dev This contract inherits functionalties from the contracts:
/// - BondingCurveFundingManagerBase
/// - RedeemingBondingCurveFundingManagerBase
/// The contract should be used by the Orchestrator Owner or manager to manage all the configuration for the
/// bonding curve as well as the opening and closing of the issuance and redeeming functionalities.
/// The contract implements the formulaWrapper functions enforced by the upstream contracts,
/// using the Topos formula to calculate the issuance/redeeming rate.
contract ToposBondingCurveFundingManager is
    IRepayer,
    IToposBondingCurveFundingManager,
    RedeemingBondingCurveFundingManagerBase
{
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(RedeemingBondingCurveFundingManagerBase)
        returns (bool)
    {
        return interfaceId == type(IToposBondingCurveFundingManager).interfaceId
            || super.supportsInterface(interfaceId);
    }

    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------
    // Constants

    /// @dev Minimum collateral reserve
    uint public constant MIN_RESERVE = 1 ether;
    /// @dev Max seizable amount is 1% expressed in BPS
    uint64 public constant MAX_SEIZE = 100;
    /// @dev Max fee for selling is TODO: See Qs, expressed in BPS
    uint64 public constant MAX_SELL_FEE = 100; // BPS, 2.5%
    /// @dev Time interval between seizes
    uint64 public constant SEIZE_DELAY = 7 days;

    bytes32 public constant RISK_MANAGER_ROLE = "RISK_MANAGER";
    bytes32 public constant COVER_MANAGER_ROLE = "COVER_MANAGER";

    //--------------------------------------------------------------------------
    // Storage

    /// @dev The interface of the Formula used to calculate the issuance and redeeming amount.
    IToposFormula public formula;
    /// @notice Repayable amount collateral which can be pulled from the contract by the liquidity pool
    uint public repayableAmount;
    /// @dev The current seize percentage expresses in BPS
    uint64 public currentSeize = MAX_SEIZE;
    /// @dev Address of the liquidity pool who has access to the collateral held by the funding manager
    /// through the Repayer functionality
    ILiquidityPool public liquidityPool;
    /// @dev Token that is accepted by this funding manager for deposits.
    IERC20 private _token;
    /// @dev Tracks last seize timestamp to determine eligibility for subsequent seizures based on SEIZE_DELAY.
    uint lastSeizeTimestamp; //TODO: Test if this needs to be initiated?
    /// @dev the amount of value that is needed to operate the Topos protocol according to market size
    /// and conditions
    uint public capitalRequired;
    /// @dev Base price multiplier in the bonding curve formula
    uint public basePriceMultiplier = 0.000001 ether;
    /// @dev (basePriceMultiplier / capitalRequired)
    uint public basePriceToCapitalRatio;

    //--------------------------------------------------------------------------
    // Init Function

    /// @inheritdoc Module
    function init(
        IOrchestrator orchestrator_,
        Metadata memory metadata,
        bytes memory configData
    ) external override(Module) initializer {
        __Module_init(orchestrator_, metadata);

        address _acceptedToken;
        IssuanceToken memory issuanceToken;
        BondingCurveProperties memory bondingCurveProperties;
        address _liquidityPool;

        (issuanceToken, bondingCurveProperties, _acceptedToken, _liquidityPool)
        = abi.decode(
            configData,
            (IssuanceToken, BondingCurveProperties, address, address)
        );

        __ERC20_init(
            string(abi.encodePacked(issuanceToken.name)),
            string(abi.encodePacked(issuanceToken.symbol))
        );

        // Set collateral token
        _token = IERC20(_acceptedToken);
        // Set liquidity pool address
        liquidityPool = ILiquidityPool(_liquidityPool);
        // Set formula contract
        formula = IToposFormula(bondingCurveProperties.formula);
        _setCapitalRequired(bondingCurveProperties.capitalRequired);
        // Set sell fee to Max fee at initiation
        _setSellFee(MAX_SELL_FEE);

        // TODO:
        // - Add reserve address to init
        // - Sort out if we need issuance token decimal and collateral decimal for calculations
    }

    //--------------------------------------------------------------------------
    // Modifiers

    modifier onlyLiquidityPool() {
        if (_msgSender() != address(liquidityPool)) {
            revert ToposBondingCurveFundingManager__InvalidLiquidityPool(
                _msgSender()
            );
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Public Functions

    /// @notice Buy tokens on behalf of a specified receiver address.
    /// @dev
    /// @param _receiver The address that will receive the bought tokens.
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buyFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(BondingCurveFundingManagerBase)
        validReceiver(_receiver)
        buyingIsEnabled
    {
        _buyOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Buy tokens for the sender's address.
    /// @dev
    /// @param _depositAmount The amount of collateral token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function buy(uint _depositAmount, uint _minAmountOut)
        external
        override(BondingCurveFundingManagerBase)
        buyingIsEnabled
    {
        _buyOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @notice Redeem tokens on behalf of a specified receiver address.
    /// @dev
    /// @param _receiver The address that will receive the redeemed tokens.
    /// @param _depositAmount The amount of issued token to deposited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sellFor(address _receiver, uint _depositAmount, uint _minAmountOut)
        external
        override(RedeemingBondingCurveFundingManagerBase)
        validReceiver(_receiver)
        sellingIsEnabled
    {
        _sellOrder(_receiver, _depositAmount, _minAmountOut);
    }

    /// @notice Sell collateral for the sender's address.
    /// @dev
    /// @param _depositAmount The amount of issued token depoisited.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    /// @param _minAmountOut The minimum acceptable amount the user expects to receive from the transaction.
    function sell(uint _depositAmount, uint _minAmountOut)
        external
        override(RedeemingBondingCurveFundingManagerBase)
        sellingIsEnabled
    {
        _sellOrder(_msgSender(), _depositAmount, _minAmountOut);
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function burnIssuanceToken(uint _amount) external {
        _burn(_msgSender(), _amount);
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function burnIssuanceTokenFor(address _owner, uint _amount) external {
        if (_owner != _msgSender()) {
            // Does not update allowance if set to infinite
            _spendAllowance(_owner, _msgSender(), _amount);
        }
        // Will revert if balance < amount
        _burn(_owner, _amount);
    }

    /// @notice Calculates and returns the static price for buying the issuance token.
    /// @return uint The static price for buying the issuance token
    function getStaticPriceForBuying()
        external
        view
        override(BondingCurveFundingManagerBase)
        returns (uint)
    {
        return
            formula.spotPrice(_getCapitalAvailable(), basePriceToCapitalRatio);
    }

    /// @notice Calculates and returns the static price for selling the issuance token.
    /// @return uint The static price for selling the issuance token
    function getStaticPriceForSelling()
        external
        view
        override(RedeemingBondingCurveFundingManagerBase)
        returns (uint)
    {
        return
            formula.spotPrice(_getCapitalAvailable(), basePriceToCapitalRatio);
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function getSaleFeeForAmount(uint _amountIn)
        external
        view
        returns (uint feeAmount)
    {
        ( /* netAmount */ , feeAmount) =
            _calculateNetAmountAndFee(_amountIn, sellFee);
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function getPurchaseFeeForAmount(uint _amountIn)
        external
        view
        returns (uint feeAmount)
    {
        ( /* netAmount */ , feeAmount) =
            _calculateNetAmountAndFee(_amountIn, buyFee);
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) external pure returns (uint) {
        return _calculateBasePriceToCapitalRatio(
            _capitalRequired, _basePriceMultiplier
        );
    }

    //--------------------------------------------------------------------------
    // Implementation Specific Public Functions

    /// @inheritdoc IRepayer
    function getRepayableAmount() external view returns (uint) {
        return _getRepayableAmount();
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function seizable() public view returns (uint) {
        uint currentBalance = _token.balanceOf(address(this));

        return (currentBalance * currentSeize) / 10_000;
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IFundingManager
    function token() public view returns (IERC20) {
        return _token;
    }

    //--------------------------------------------------------------------------
    // OnlyLiquidtyPool Functions

    /// @inheritdoc IRepayer
    function transferRepayment(address _to, uint _amount)
        external
        validReceiver(_to)
        onlyLiquidityPool
    {
        if (_amount > _getRepayableAmount()) {
            revert Repayer__InsufficientCollateralForRepayerTransfer();
        }
        __Module_orchestrator.fundingManager().token().safeTransfer(
            _to, _amount
        );
    }

    //--------------------------------------------------------------------------
    // OnlyCoverManager Functions

    /// @inheritdoc IToposBondingCurveFundingManager
    function seize(uint _amount) public onlyModuleRole(COVER_MANAGER_ROLE) {
        uint s = seizable();
        if (_amount > s) {
            revert ToposBondingCurveFundingManager__InvalidSeizeAmount(s);
        }
        // solhint-disable-next-line not-rely-on-time
        else if (lastSeizeTimestamp + SEIZE_DELAY > block.timestamp) {
            revert ToposBondingCurveFundingManager__SeizeTimeout(
                lastSeizeTimestamp + SEIZE_DELAY
            );
        }

        uint capitalAvailable = _getCapitalAvailable();
        // The asset pool must never be empty.
        if (capitalAvailable - _amount < MIN_RESERVE) {
            _amount = capitalAvailable - MIN_RESERVE;
        }

        // solhint-disable-next-line not-rely-on-time
        lastSeizeTimestamp = uint64(block.timestamp);
        _token.transfer(_msgSender(), _amount);
        emit CollateralSeized(_amount);
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function adjustSeize(uint64 _seize)
        public
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (_seize > MAX_SEIZE) {
            revert ToposBondingCurveFundingManager__InvalidSeize(_seize);
        }
        currentSeize = _seize;
    }

    /// @inheritdoc IRedeemingBondingCurveFundingManagerBase
    function setSellFee(uint _fee)
        external
        override(RedeemingBondingCurveFundingManagerBase)
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (_fee > MAX_SELL_FEE) {
            revert ToposBondingCurveFundingManager__InvalidFeePercentage(_fee);
        }
        _setSellFee(_fee);
    }

    /// @inheritdoc IRepayer
    function setRepayableAmount(uint _amount)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (_amount > _getSmallerCaCr()) {
            revert ToposBondingCurveFundingManager__InvalidInputAmount();
        }
        emit RepayableAmountChanged(_amount, repayableAmount);
        repayableAmount = _amount;
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function setLiquidityPoolContract(ILiquidityPool _lp)
        external
        onlyModuleRole(COVER_MANAGER_ROLE)
    {
        if (address(_lp) == address(0)) {
            revert ToposBondingCurveFundingManager__InvalidInputAddress();
        }
        emit LiquidityPoolChanged(_lp, liquidityPool);
        liquidityPool = _lp;
    }

    //--------------------------------------------------------------------------
    // OnlyRiskManager Functions

    /// @inheritdoc IToposBondingCurveFundingManager
    function setCapitalRequired(uint _newCapitalRequired)
        public
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setCapitalRequired(_newCapitalRequired);
    }

    /// @inheritdoc IToposBondingCurveFundingManager
    function setBaseMultiplier(uint _newBaseMultiplier)
        public
        onlyModuleRole(RISK_MANAGER_ROLE)
    {
        _setBaseMultiplier(_newBaseMultiplier);
    }

    //--------------------------------------------------------------------------
    // Upstream Function Implementations

    /// @dev Calculates the amount of tokens to mint for a given deposit amount using the formula contract.
    /// This internal function is an override of BondingCurveFundingManagerBase's abstract function.
    /// @param _depositAmount The amount of collateral deposited to purchase tokens.
    /// @return mintAmount The amount of tokens that will be minted.
    function _issueTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(BondingCurveFundingManagerBase)
        returns (uint mintAmount)
    {
        // Subtract fee collected from capital held by contract
        uint capitalAvailable = _getCapitalAvailable();
        mintAmount = formula.tokenOut(
            _depositAmount, capitalAvailable, basePriceToCapitalRatio
        );
    }

    /// @dev Calculates the amount of collateral to be received when redeeming a given amount of tokens.
    /// This internal function is an override of RedeemingBondingCurveFundingManagerBase's abstract function.
    /// @param _depositAmount The amount of tokens to be redeemed for collateral.
    /// @return redeemAmount The amount of collateral that will be received.
    function _redeemTokensFormulaWrapper(uint _depositAmount)
        internal
        view
        override(RedeemingBondingCurveFundingManagerBase)
        returns (uint redeemAmount)
    {
        // Subtract fee collected from capital held by contract
        uint capitalAvailable = _getCapitalAvailable();
        redeemAmount = formula.tokenIn(
            _depositAmount, capitalAvailable, basePriceToCapitalRatio
        );

        // The asset pool must never be empty.
        if (capitalAvailable - redeemAmount < MIN_RESERVE) {
            redeemAmount = capitalAvailable - MIN_RESERVE;
        }
    }

    //--------------------------------------------------------------------------
    // Internal Functions

    /// @dev Returns the collateral available in this contract, subtracted by the fee collected
    /// @return uint Capital available in contract
    function _getCapitalAvailable() internal view returns (uint) {
        return _token.balanceOf(address(this)) - tradeFeeCollected;
    }

    function _setCapitalRequired(uint _newCapitalRequired) internal {
        if (_newCapitalRequired == 0) {
            revert ToposBondingCurveFundingManager__InvalidInputAmount();
        }
        emit CapitalRequiredChanged(capitalRequired, _newCapitalRequired);
        capitalRequired = _newCapitalRequired;
        _updateVariables();
    }

    function _setBaseMultiplier(uint _newBasePriceMultiplier) internal {
        if (_newBasePriceMultiplier == 0) {
            revert ToposBondingCurveFundingManager__InvalidInputAmount();
        }
        emit BaseMultiplierChanged(basePriceMultiplier, _newBasePriceMultiplier);
        basePriceMultiplier = _newBasePriceMultiplier;
        _updateVariables();
    }

    /// @notice If the repayable amount was not defined, it is automatically set to the smaller between the Ca and the Cr value
    /// @notice The repayable amount as maximum is applied when is gt 0 and is lt the smallest between Cr and Ca
    function _getRepayableAmount() internal view returns (uint) {
        uint _repayable = _getSmallerCaCr();
        return (repayableAmount == 0 || repayableAmount > _repayable)
            ? _repayable
            : repayableAmount;
    }

    /// @notice If the balance of the Capital Available (Ca) is larger than the Capital Requested (Cr), the repayable amount can be lte Cr
    /// @notice If the Ca is lt Cr, the max repayable amount is the Ca
    function _getSmallerCaCr() internal view returns (uint) {
        uint _ca = _getCapitalAvailable();
        uint _cr = capitalRequired;
        return _ca > _cr ? _cr : _ca;
    }

    /// @dev Precomputes and sets the price multiplier to capital ratio
    function _updateVariables() internal {
        basePriceToCapitalRatio = _calculateBasePriceToCapitalRatio(
            capitalRequired, basePriceMultiplier
        );
    }

    /// @dev Internal function which calculates the price multiplier to capital ratio
    function _calculateBasePriceToCapitalRatio(
        uint _capitalRequired,
        uint _basePriceMultiplier
    ) internal pure returns (uint _basePriceToCapitalRatio) {
        _basePriceToCapitalRatio = FixedPointMathLib.fdiv(
            _basePriceMultiplier, _capitalRequired, FixedPointMathLib.WAD
        );
        if (_basePriceToCapitalRatio > 1e36) {
            revert ToposBondingCurveFundingManager__InvalidInputAmount();
        }
    }
}
