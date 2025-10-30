// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEulerSwapCallee} from "./interfaces/IEulerSwapCallee.sol";
import {IEVault} from "evk/EVault/IEVault.sol";

import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {UniswapHook} from "./UniswapHook.sol";
import {CtxLib} from "./libraries/CtxLib.sol";
import {QuoteLib} from "./libraries/QuoteLib.sol";
import {SwapLib} from "./libraries/SwapLib.sol";

contract EulerSwap is IEulerSwap, UniswapHook {
    bytes32 public constant curve = bytes32("EulerSwap v2");
    address public immutable managementImpl;

    error AmountTooBig();

    /// @notice Emitted upon EulerSwap instance creation or reconfiguration.
    event EulerSwapConfigured(DynamicParams dParams, InitialState initialState);
    /// @notice Emitted upon EulerSwap instance creation or reconfiguration.
    event EulerSwapManagerSet(address indexed manager, bool installed);

    constructor(address evc_, address protocolFeeConfig_, address poolManager_, address managementImpl_)
        UniswapHook(evc_, protocolFeeConfig_, poolManager_)
    {
        managementImpl = managementImpl_;
    }

    function delegateToManagementImpl() internal {
        (bool success, bytes memory result) = managementImpl.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(32, result), mload(result))
            }
        }
    }

    /// @inheritdoc IEulerSwap
    function activate(DynamicParams calldata, InitialState calldata) external {
        delegateToManagementImpl();

        // Uniswap hook activation

        activateHook(CtxLib.getStaticParams());
    }

    /// @inheritdoc IEulerSwap
    function setManager(address, bool) external {
        delegateToManagementImpl();
    }

    /// @inheritdoc IEulerSwap
    function reconfigure(DynamicParams calldata, InitialState calldata) external {
        delegateToManagementImpl();
    }

    /// @inheritdoc IEulerSwap
    function managers(address manager) external view returns (bool installed) {
        CtxLib.State storage s = CtxLib.getState();
        return s.managers[manager];
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

        return evc.isAccountOperatorAuthorized(sParams.eulerAccount, address(this));
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

        SwapLib.SwapContext memory ctx = SwapLib.init(address(evc), protocolFeeConfig, _msgSender(), to);
        SwapLib.setAmountsOut(ctx, amount0Out, amount1Out);
        SwapLib.invokeBeforeSwapHook(ctx);

        // Optimistically send tokens

        SwapLib.doWithdraws(ctx);

        // Invoke callback

        if (data.length > 0) IEulerSwapCallee(to).eulerSwapCall(_msgSender(), amount0Out, amount1Out, data);

        // Deposit all available funds

        SwapLib.setAmountsIn(
            ctx, IERC20(ctx.asset0).balanceOf(address(this)), IERC20(ctx.asset1).balanceOf(address(this))
        );
        SwapLib.doDeposits(ctx);

        // Verify curve invariant is satisfied

        SwapLib.finish(ctx);
    }
}
