// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEVault} from "evk/EVault/IEVault.sol";

import {CtxLib} from "./CtxLib.sol";
import {CurveLib} from "./CurveLib.sol";
import {FundsLib} from "./FundsLib.sol";
import {QuoteLib} from "./QuoteLib.sol";
import {IEulerSwap} from "../interfaces/IEulerSwap.sol";
import "../interfaces/IEulerSwapHookTarget.sol";

library SwapLib {
    using SafeERC20 for IERC20;

    /// @notice Emitted after every swap.
    ///   * `sender` is the initiator of the swap, or the Router when invoked via hook.
    ///   * `amount0In` and `amount1In` are after fees have been subtracted.
    ///   * `fee0` and `fee1` are the amount of input tokens received fees.
    ///   * `reserve0` and `reserve1` are the pool's new reserves (after the swap).
    ///   * `to` is the specified recipient of the funds, or the PoolManager when invoked via hook.
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 fee0,
        uint256 fee1,
        uint112 reserve0,
        uint112 reserve1,
        address indexed to
    );

    struct SwapContext {
        // Populated by init
        address evc;
        IEulerSwap.StaticParams sParams;
        IEulerSwap.DynamicParams dParams;
        address asset0;
        address asset1;
        address sender;
        address to;
        // Amount parameters
        uint256 amount0InFull;
        uint256 amount1InFull;
        uint256 amount0Out;
        uint256 amount1Out;
        // Internal
        uint256 amount0In; // full minus fees
        uint256 amount1In; // full minus fees
    }

    function init(address evc, address sender, address to) internal view returns (SwapContext memory ctx) {
        ctx.evc = evc;
        ctx.sParams = CtxLib.getStaticParams();
        ctx.dParams = CtxLib.getDynamicParams();

        ctx.asset0 = IEVault(ctx.sParams.supplyVault0).asset();
        ctx.asset1 = IEVault(ctx.sParams.supplyVault1).asset();
        ctx.sender = sender;
        ctx.to = to;

        require(ctx.dParams.expiration == 0 || ctx.dParams.expiration > block.timestamp, QuoteLib.Expired());
    }

    function amounts(
        SwapContext memory ctx,
        uint256 amount0InFull,
        uint256 amount1InFull,
        uint256 amount0Out,
        uint256 amount1Out
    ) internal {
        ctx.amount0InFull = amount0InFull;
        ctx.amount1InFull = amount1InFull;
        ctx.amount0Out = amount0Out;
        ctx.amount1Out = amount1Out;

        if ((ctx.dParams.swapHookedOperations & EULER_SWAP_HOOK_BEFORE_SWAP) != 0) {
            IEulerSwapHookTarget(ctx.dParams.swapHook).beforeSwap(
                amount0InFull, amount1InFull, amount0Out, amount1Out, ctx.sender, ctx.to
            );
        }
    }

    function doDeposits(SwapContext memory ctx) internal {
        doDeposit(ctx, true);
        doDeposit(ctx, false);
    }

    function doWithdraws(SwapContext memory ctx) internal {
        doWithdraw(ctx, false);
        doWithdraw(ctx, true);
    }

    function finish(SwapContext memory ctx) internal {
        CtxLib.State storage s = CtxLib.getState();

        uint256 newReserve0 = s.reserve0 + ctx.amount0In - ctx.amount0Out;
        uint256 newReserve1 = s.reserve1 + ctx.amount1In - ctx.amount1Out;

        require(CurveLib.verify(ctx.dParams, newReserve0, newReserve1), CurveLib.CurveViolation());

        s.reserve0 = uint112(newReserve0);
        s.reserve1 = uint112(newReserve1);

        uint256 fee0 = ctx.amount0InFull - ctx.amount0In;
        uint256 fee1 = ctx.amount1InFull - ctx.amount1In;

        emit Swap(
            ctx.sender,
            ctx.amount0In,
            ctx.amount1In,
            ctx.amount0Out,
            ctx.amount1Out,
            fee0,
            fee1,
            s.reserve0,
            s.reserve1,
            ctx.to
        );

        if ((ctx.dParams.swapHookedOperations & EULER_SWAP_HOOK_AFTER_SWAP) != 0) {
            s.status = 1; // Unlock the reentrancy guard during afterSwap, allowing hook to reconfigure()

            IEulerSwapHookTarget(ctx.dParams.swapHook).afterSwap(
                ctx.amount0In,
                ctx.amount1In,
                ctx.amount0Out,
                ctx.amount1Out,
                fee0,
                fee1,
                ctx.sender,
                ctx.to,
                s.reserve0,
                s.reserve1
            );

            s.status = 2;
        }
    }

    // Private

    function doDeposit(SwapContext memory ctx, bool asset0IsInput) private {
        uint256 amount = asset0IsInput ? ctx.amount0InFull : ctx.amount1InFull;
        if (amount == 0) return;

        address assetInput = asset0IsInput ? ctx.asset0 : ctx.asset1;

        uint256 fee = QuoteLib.getFee(ctx.dParams, asset0IsInput);
        require(fee < 1e18, QuoteLib.SwapRejected());

        uint256 feeAmount = amount * fee / 1e18;

        // Slice off protocol fee

        if (ctx.sParams.protocolFeeRecipient != address(0)) {
            uint256 protocolFeeAmount = feeAmount * ctx.sParams.protocolFee / 1e18;

            if (protocolFeeAmount != 0) {
                IERC20(assetInput).safeTransfer(ctx.sParams.protocolFeeRecipient, protocolFeeAmount);

                amount -= protocolFeeAmount;
                feeAmount -= protocolFeeAmount;
            }
        }

        // Slice off separate LP fee recipient

        if (ctx.sParams.feeRecipient != address(0)) {
            IERC20(assetInput).safeTransfer(ctx.sParams.feeRecipient, feeAmount);

            amount -= feeAmount;
            feeAmount = 0;
        }

        // Deposit remainder on behalf of eulerAccount

        amount = FundsLib.depositAssets(
            ctx.evc,
            ctx.sParams.eulerAccount,
            asset0IsInput ? ctx.sParams.supplyVault0 : ctx.sParams.supplyVault1,
            asset0IsInput ? ctx.sParams.borrowVault0 : ctx.sParams.borrowVault1,
            amount
        );

        amount = amount > feeAmount ? amount - feeAmount : 0;

        if (asset0IsInput) ctx.amount0In = amount;
        else ctx.amount1In = amount;
    }

    function doWithdraw(SwapContext memory ctx, bool asset0IsInput) private {
        uint256 amount = asset0IsInput ? ctx.amount1Out : ctx.amount0Out;
        if (amount == 0) return;

        FundsLib.withdrawAssets(
            ctx.evc,
            ctx.sParams.eulerAccount,
            asset0IsInput ? ctx.sParams.supplyVault1 : ctx.sParams.supplyVault0,
            asset0IsInput ? ctx.sParams.borrowVault1 : ctx.sParams.borrowVault0,
            amount,
            ctx.to
        );
    }
}
