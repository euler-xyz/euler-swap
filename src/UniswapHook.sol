// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {
    BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {IEVault} from "evk/EVault/IEVault.sol";

import {EulerSwapBase} from "./EulerSwapBase.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {CtxLib} from "./libraries/CtxLib.sol";
import {QuoteLib} from "./libraries/QuoteLib.sol";
import {CurveLib} from "./libraries/CurveLib.sol";
import {FundsLib} from "./libraries/FundsLib.sol";
import {SwapLib} from "./libraries/SwapLib.sol";

abstract contract UniswapHook is EulerSwapBase, BaseHook {
    using SafeCast for uint256;

    address public immutable protocolFeeConfig;

    PoolKey internal _poolKey;

    constructor(address evc_, address protocolFeeConfig_, address _poolManager)
        EulerSwapBase(evc_)
        BaseHook(IPoolManager(_poolManager))
    {
        protocolFeeConfig = protocolFeeConfig_;
    }

    function activateHook(IEulerSwap.StaticParams memory sParams) internal nonReentrant {
        if (address(poolManager) == address(0)) return;

        Hooks.validateHookPermissions(this, getHookPermissions());

        address asset0Addr = IEVault(sParams.supplyVault0).asset();
        address asset1Addr = IEVault(sParams.supplyVault1).asset();

        _poolKey = PoolKey({
            currency0: Currency.wrap(asset0Addr),
            currency1: Currency.wrap(asset1Addr),
            fee: 0, // hard-coded fee since it may change
            tickSpacing: 1, // hard-coded tick spacing, as it's unused
            hooks: IHooks(address(this))
        });

        // create the pool on v4, using starting price as sqrtPrice(1/1) * Q96
        poolManager.initialize(_poolKey, 79228162514264337593543950336);
    }

    /// @dev Helper function to return the poolKey as its struct type
    function poolKey() external view returns (PoolKey memory) {
        return _poolKey;
    }

    /// @dev Prevent hook address validation in constructor, which is not needed
    /// because hook instances are proxies. Instead, the address is validated
    /// in activateHook().
    function validateHookAddress(BaseHook _this) internal pure override {}

    function _beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        nonReentrant
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        SwapLib.SwapContext memory ctx = SwapLib.init(address(evc), protocolFeeConfig, sender, msg.sender);

        uint256 amountIn;
        uint256 amountOut;
        BeforeSwapDelta returnDelta;
        bool isExactInput = params.amountSpecified < 0;

        if (isExactInput) {
            amountIn = uint256(-params.amountSpecified);
            amountOut = QuoteLib.computeQuote(address(evc), ctx.sParams, ctx.dParams, params.zeroForOne, amountIn, true);
        } else {
            amountOut = uint256(params.amountSpecified);
            amountIn =
                QuoteLib.computeQuote(address(evc), ctx.sParams, ctx.dParams, params.zeroForOne, amountOut, false);
        }

        if (params.zeroForOne) {
            SwapLib.setAmountsOut(ctx, 0, amountOut);
            SwapLib.setAmountsIn(ctx, amountIn, 0);
        } else {
            SwapLib.setAmountsOut(ctx, amountOut, 0);
            SwapLib.setAmountsIn(ctx, 0, amountIn);
        }

        SwapLib.invokeBeforeSwapHook(ctx);

        // return the delta to the PoolManager, so it can process the accounting
        // exact input:
        //   specifiedDelta = positive, to offset the input token taken by the hook (negative delta)
        //   unspecifiedDelta = negative, to offset the credit of the output token paid by the hook (positive delta)
        // exact output:
        //   specifiedDelta = negative, to offset the output token paid by the hook (positive delta)
        //   unspecifiedDelta = positive, to offset the input token taken by the hook (negative delta)
        returnDelta = isExactInput
            ? toBeforeSwapDelta(amountIn.toInt128(), -(amountOut.toInt128()))
            : toBeforeSwapDelta(-(amountOut.toInt128()), amountIn.toInt128());

        // take the input token, from the PoolManager to the Euler vault
        // the debt will be paid by the swapper via the swap router
        poolManager.take(params.zeroForOne ? key.currency0 : key.currency1, address(this), amountIn);
        SwapLib.doDeposits(ctx);

        // pay the output token, to the PoolManager from an Euler vault
        // the credit will be forwarded to the swap router, which then forwards it to the swapper
        poolManager.sync(params.zeroForOne ? key.currency1 : key.currency0);
        SwapLib.doWithdraws(ctx);
        poolManager.settle();

        SwapLib.finish(ctx);

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        /**
         * @dev Hook Permissions without overrides:
         * - beforeInitialize, beforeDoate, beforeAddLiquidity
         * We use BaseHook's original reverts to *intentionally* revert
         *
         * beforeInitialize: the hook reverts for initializations NOT going through EulerSwap.activateHook()
         * we want to prevent users from initializing other pairs with the same hook address
         *
         * beforeDonate: because the hook does not support native concentrated liquidity, any
         * donations are permanently irrecoverable. The hook reverts on beforeDonate to prevent accidental misusage
         *
         * beforeAddLiquidity: the hook reverts to prevent v3-CLAMM positions
         * because the hook is a "custom curve", any concentrated liquidity position sits idle and entirely unused
         * to protect users from accidentally creating non-productive positions, the hook reverts on beforeAddLiquidity
         */
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: true,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
