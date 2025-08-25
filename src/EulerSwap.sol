// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEulerSwapCallee} from "./interfaces/IEulerSwapCallee.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";

import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {UniswapHook} from "./UniswapHook.sol";
import {CtxLib} from "./libraries/CtxLib.sol";
import {FundsLib} from "./libraries/FundsLib.sol";
import {CurveLib} from "./libraries/CurveLib.sol";
import {QuoteLib} from "./libraries/QuoteLib.sol";
import {SwapLib} from "./libraries/SwapLib.sol";

contract EulerSwap is IEulerSwap, EVCUtil, UniswapHook {
    bytes32 public constant curve = bytes32("EulerSwap v2");

    error Unauthorized();
    error Locked();
    error AlreadyActivated();
    error BadStaticParam();
    error BadDynamicParam();
    error AmountTooBig();
    error AssetsOutOfOrderOrEqual();
    error InvalidAssets();

    /// @notice Addresses configured as managers. Managers can reconfigure the pool parameters.
    mapping(address manager => bool installed) public managers;

    /// @notice Emitted upon EulerSwap instance creation or reconfiguration.
    event EulerSwapConfigured(DynamicParams dParams, InitialState initialState);
    /// @notice Emitted upon EulerSwap instance creation or reconfiguration.
    event EulerSwapManagerSet(address indexed manager, bool installed);

    constructor(address evc_, address poolManager_) EVCUtil(evc_) UniswapHook(evc_, poolManager_) {
        CtxLib.State storage s = CtxLib.getState();

        s.status = 2; // can only be used via delegatecall proxy
    }

    modifier nonReentrant() {
        CtxLib.State storage s = CtxLib.getState();

        require(s.status == 1, Locked());
        s.status = 2;
        _;
        s.status = 1;
    }

    modifier nonReentrantView() {
        CtxLib.State storage s = CtxLib.getState();
        require(s.status != 2, Locked());

        _;
    }

    function installDynamicParams(
        CtxLib.State storage s,
        DynamicParams memory dParams,
        InitialState memory initialState
    ) internal {
        require(dParams.minReserve0 <= dParams.equilibriumReserve0, BadDynamicParam());
        require(dParams.minReserve1 <= dParams.equilibriumReserve1, BadDynamicParam());
        require(dParams.minReserve0 <= initialState.reserve0, BadDynamicParam());
        require(dParams.minReserve1 <= initialState.reserve1, BadDynamicParam());

        require(dParams.priceX > 0 && dParams.priceY > 0, BadDynamicParam());
        require(dParams.priceX <= 1e24 && dParams.priceY <= 1e24, BadDynamicParam());
        require(dParams.concentrationX <= 1e18 && dParams.concentrationY <= 1e18, BadDynamicParam());

        require(dParams.fee0 <= 1e18 && dParams.fee1 <= 1e18, BadDynamicParam());

        require(CurveLib.verify(dParams, initialState.reserve0, initialState.reserve1), CurveLib.CurveViolation());

        CtxLib.writeDynamicParamsToStorage(dParams);
        s.reserve0 = initialState.reserve0;
        s.reserve1 = initialState.reserve1;

        emit EulerSwapConfigured(dParams, initialState);
    }

    /// @inheritdoc IEulerSwap
    function activate(DynamicParams calldata dParams, InitialState calldata initialState) external {
        CtxLib.State storage s = CtxLib.getState();
        StaticParams memory sParams = CtxLib.getStaticParams();

        require(s.status == 0, AlreadyActivated());
        s.status = 1;

        // Static parameters

        {
            address asset0Addr = IEVault(sParams.supplyVault0).asset();
            address asset1Addr = IEVault(sParams.supplyVault1).asset();

            require(
                sParams.borrowVault0 == address(0) || IEVault(sParams.borrowVault0).asset() == asset0Addr,
                InvalidAssets()
            );
            require(
                sParams.borrowVault1 == address(0) || IEVault(sParams.borrowVault1).asset() == asset1Addr,
                InvalidAssets()
            );

            require(asset0Addr != address(0) && asset1Addr != address(0), InvalidAssets());
            require(asset0Addr < asset1Addr, AssetsOutOfOrderOrEqual());
        }

        require(sParams.eulerAccount != sParams.feeRecipient, BadStaticParam()); // set feeRecipient to 0 instead

        // Dynamic parameters

        if (initialState.reserve0 != 0) {
            require(
                !CurveLib.verify(dParams, initialState.reserve0 - 1, initialState.reserve1), CurveLib.CurveViolation()
            );
        }
        if (initialState.reserve1 != 0) {
            require(
                !CurveLib.verify(dParams, initialState.reserve0, initialState.reserve1 - 1), CurveLib.CurveViolation()
            );
        }

        installDynamicParams(s, dParams, initialState);

        // Configure external contracts

        FundsLib.approveVault(sParams.supplyVault0);
        FundsLib.approveVault(sParams.supplyVault1);

        if (sParams.borrowVault0 != address(0) && sParams.borrowVault0 != sParams.supplyVault0) {
            FundsLib.approveVault(sParams.borrowVault0);
        }
        if (sParams.borrowVault1 != address(0) && sParams.borrowVault1 != sParams.supplyVault1) {
            FundsLib.approveVault(sParams.borrowVault1);
        }

        IEVC(evc).enableCollateral(sParams.eulerAccount, sParams.supplyVault0);
        IEVC(evc).enableCollateral(sParams.eulerAccount, sParams.supplyVault1);

        // Uniswap hook activation

        if (address(poolManager) != address(0)) activateHook(sParams);
    }

    /// @inheritdoc IEulerSwap
    function setManager(address manager, bool installed) external {
        StaticParams memory sParams = CtxLib.getStaticParams();

        require(_msgSender() == sParams.eulerAccount, Unauthorized());
        managers[manager] = installed;

        emit EulerSwapManagerSet(manager, installed);
    }

    /// @inheritdoc IEulerSwap
    function reconfigure(DynamicParams calldata dParams, InitialState calldata initialState) external nonReentrant {
        CtxLib.State storage s = CtxLib.getState();
        StaticParams memory sParams = CtxLib.getStaticParams();
        DynamicParams memory oldDParams = CtxLib.getDynamicParams();

        {
            address sender = _msgSender();
            require(sender == sParams.eulerAccount || managers[sender] || sender == oldDParams.swapHook, Unauthorized());
        }

        installDynamicParams(s, dParams, initialState);
    }

    /// @inheritdoc IEulerSwap
    function getStaticParams() external pure returns (StaticParams memory) {
        return CtxLib.getStaticParams();
    }

    /// @inheritdoc IEulerSwap
    function getDynamicParams() external pure returns (DynamicParams memory) {
        return CtxLib.getDynamicParams();
    }

    /// @inheritdoc IEulerSwap
    function getAssets() external view returns (address asset0, address asset1) {
        StaticParams memory sParams = CtxLib.getStaticParams();

        asset0 = IEVault(sParams.supplyVault0).asset();
        asset1 = IEVault(sParams.supplyVault1).asset();
    }

    /// @inheritdoc IEulerSwap
    function getReserves() external view nonReentrantView returns (uint112, uint112, uint32) {
        CtxLib.State storage s = CtxLib.getState();

        return (s.reserve0, s.reserve1, s.status);
    }

    /// @inheritdoc IEulerSwap
    function isInstalled() external view nonReentrantView returns (bool) {
        StaticParams memory sParams = CtxLib.getStaticParams();

        return IEVC(evc).isAccountOperatorAuthorized(sParams.eulerAccount, address(this));
    }

    /// @inheritdoc IEulerSwap
    function computeQuote(address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        external
        view
        nonReentrantView
        returns (uint256)
    {
        StaticParams memory sParams = CtxLib.getStaticParams();
        DynamicParams memory dParams = CtxLib.getDynamicParams();

        return QuoteLib.computeQuote(
            address(evc), sParams, dParams, QuoteLib.checkTokens(sParams, tokenIn, tokenOut), amount, exactIn
        );
    }

    /// @inheritdoc IEulerSwap
    function getLimits(address tokenIn, address tokenOut)
        external
        view
        nonReentrantView
        returns (uint256 inLimit, uint256 outLimit)
    {
        StaticParams memory sParams = CtxLib.getStaticParams();
        DynamicParams memory dParams = CtxLib.getDynamicParams();

        if (!evc.isAccountOperatorAuthorized(sParams.eulerAccount, address(this))) return (0, 0);
        if (dParams.expiration != 0 && dParams.expiration <= block.timestamp) return (0, 0);

        bool asset0IsInput = QuoteLib.checkTokens(sParams, tokenIn, tokenOut);

        uint256 fee = QuoteLib.getFeeReadOnly(dParams, asset0IsInput);
        if (fee >= 1e18) return (0, 0);

        (inLimit, outLimit) = QuoteLib.calcLimits(sParams, dParams, asset0IsInput, fee);
        if (outLimit > 0) outLimit--; // Compensate for rounding up of exact output quotes
    }

    /// @inheritdoc IEulerSwap
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        callThroughEVC
        nonReentrant
    {
        require(amount0Out <= type(uint112).max && amount1Out <= type(uint112).max, AmountTooBig());

        // Setup context

        SwapLib.SwapContext memory ctx = SwapLib.init(address(evc), _msgSender(), to);

        SwapLib.amounts(
            ctx,
            IERC20(ctx.asset0).balanceOf(address(this)),
            IERC20(ctx.asset1).balanceOf(address(this)),
            amount0Out,
            amount1Out
        );

        // Optimistically send tokens

        SwapLib.doWithdraws(ctx);

        // Invoke callback

        if (data.length > 0) IEulerSwapCallee(to).eulerSwapCall(_msgSender(), amount0Out, amount1Out, data);

        // Deposit all available funds, adjust received amounts downward to collect fees

        SwapLib.doDeposits(ctx);

        // Verify curve invariant is satisfied

        SwapLib.finish(ctx);
    }
}
