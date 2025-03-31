// SPDX-License-Identifier: UNLICENSED
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
import {EulerSwap, IEulerSwap, IEVault} from "./EulerSwap.sol";

contract EulerSwapHook is EulerSwap, BaseHook {
    using SafeCast for uint256;

    PoolKey internal _poolKey;

    constructor(IPoolManager _manager, Params memory params, CurveParams memory curveParams)
        EulerSwap(params, curveParams)
        BaseHook(_manager)
    {
        address asset0Addr = IEVault(params.vault0).asset();
        address asset1Addr = IEVault(params.vault1).asset();

        // convert fee in WAD to pips. 0.003e18 / 1e12 = 3000 = 0.30%
        uint24 fee = uint24(params.fee / 1e12);

        _poolKey = PoolKey({
            currency0: Currency.wrap(asset0Addr),
            currency1: Currency.wrap(asset1Addr),
            fee: fee,
            tickSpacing: 60, // TODO: fix arbitrary tick spacing
            hooks: IHooks(address(this))
        });

        // create the pool on v4, using starting price as sqrtPrice(1/1) * Q96
        poolManager.initialize(_poolKey, 79228162514264337593543950336);
    }

    /// @dev Helper function to return the poolKey as its struct type
    function poolKey() external view returns (PoolKey memory) {
        return _poolKey;
    }

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // determine inbound/outbound token based on 0->1 or 1->0 swap
        bool zeroForOne = params.zeroForOne;

        uint256 amountInWithoutFee;
        uint256 amountOut;
        BeforeSwapDelta returnDelta;

        {
            (Currency inputCurrency, Currency outputCurrency) =
                zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

            uint256 amountIn;
            bool isExactInput = params.amountSpecified < 0;
            if (isExactInput) {
                amountIn = uint256(-params.amountSpecified);
                amountOut = computeQuote(zeroForOne, uint256(-params.amountSpecified), true);
            } else {
                amountIn = computeQuote(zeroForOne, uint256(params.amountSpecified), false);
                amountOut = uint256(params.amountSpecified);
            }

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
            // TODO: can we optimize the transfer by pulling from PoolManager directly to Euler?
            poolManager.take(inputCurrency, address(this), amountIn);
            amountInWithoutFee = _depositWithoutFee(zeroForOne ? vault0 : vault1, amountIn);

            // pay the output token, to the PoolManager from an Euler vault
            // the credit will be forwarded to the swap router, which then forwards it to the swapper
            poolManager.sync(outputCurrency);
            withdrawAssets(zeroForOne ? vault1 : vault0, amountOut, address(poolManager));
            poolManager.settle();
        }

        {
            uint256 newReserve0 = zeroForOne ? (reserve0 + amountInWithoutFee) : (reserve0 - amountOut);
            uint256 newReserve1 = !zeroForOne ? (reserve1 + amountInWithoutFee) : (reserve1 - amountOut);

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, Overflow());
            require(verify(newReserve0, newReserve1), CurveViolation());

            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);
        }

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    // TODO: fix salt mining & verification for the hook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {}
    function validateHookAddress(BaseHook) internal pure override {}

    error SwapLimitExceeded();
    error OperatorNotInstalled();

    function computeQuote(bool asset0IsInput, uint256 amount, bool exactIn) internal view returns (uint256) {
        require(evc.isAccountOperatorAuthorized(eulerAccount, address(this)), OperatorNotInstalled());
        require(amount <= type(uint112).max, SwapLimitExceeded());

        // exactIn: decrease received amountIn, rounding down
        if (exactIn) {
            (, uint256 protocolFeeAmount) = feeAmounts(amount);
            amount = (amount - protocolFeeAmount) * feeMultiplier / 1e18;
        }

        (uint256 inLimit, uint256 outLimit) = calcLimits(asset0IsInput);

        uint256 quote = binarySearch(amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(amount <= inLimit && quote <= outLimit, SwapLimitExceeded());
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(amount <= outLimit && quote <= inLimit, SwapLimitExceeded());
        }

        // exactOut: increase required quote(amountIn), rounding up
        if (!exactIn) quote = (quote * 1e18 + (feeMultiplier - 1)) / feeMultiplier;

        return quote;
    }

    function binarySearch(uint256 amount, bool exactIn, bool asset0IsInput) internal view returns (uint256 output) {
        int256 dx;
        int256 dy;

        if (exactIn) {
            if (asset0IsInput) dx = int256(amount);
            else dy = int256(amount);
        } else {
            if (asset0IsInput) dy = -int256(amount);
            else dx = -int256(amount);
        }

        unchecked {
            int256 reserve0New = int256(uint256(reserve0)) + dx;
            int256 reserve1New = int256(uint256(reserve1)) + dy;
            require(reserve0New > 0 && reserve1New > 0, SwapLimitExceeded());

            uint256 low;
            uint256 high = type(uint112).max;

            while (low < high) {
                uint256 mid = (low + high) / 2;
                require(mid > 0, SwapLimitExceeded());
                (uint256 a, uint256 b) = dy == 0 ? (uint256(reserve0New), mid) : (mid, uint256(reserve1New));
                if (verify(a, b)) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }

            require(high < type(uint112).max, SwapLimitExceeded()); // at least one point verified

            if (dx != 0) dy = int256(low) - reserve1New;
            else dx = int256(low) - reserve0New;
        }

        if (exactIn) {
            if (asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
        } else {
            if (asset0IsInput) output = dx >= 0 ? uint256(dx) : 0;
            else output = dy >= 0 ? uint256(dy) : 0;
        }
    }

    function calcLimits(bool asset0IsInput) internal view returns (uint256, uint256) {
        uint256 inLimit = type(uint112).max;
        uint256 outLimit = type(uint112).max;

        (IEVault vault0, IEVault vault1) = (IEVault(vault0), IEVault(vault1));
        // Supply caps on input
        {
            IEVault vault = (asset0IsInput ? vault0 : vault1);
            uint256 maxDeposit = vault.debtOf(eulerAccount) + vault.maxDeposit(eulerAccount);
            if (maxDeposit < inLimit) inLimit = maxDeposit;
        }

        // Remaining reserves of output
        {
            uint112 reserveLimit = asset0IsInput ? reserve1 : reserve0;
            if (reserveLimit < outLimit) outLimit = reserveLimit;
        }

        // Remaining cash and borrow caps in output
        {
            IEVault vault = (asset0IsInput ? vault1 : vault0);

            uint256 cash = vault.cash();
            if (cash < outLimit) outLimit = cash;

            (, uint16 borrowCap) = vault.caps();
            uint256 maxWithdraw = decodeCap(uint256(borrowCap));
            maxWithdraw = vault.totalBorrows() > maxWithdraw ? 0 : maxWithdraw - vault.totalBorrows();
            if (maxWithdraw > cash) maxWithdraw = cash;
            maxWithdraw += vault.convertToAssets(vault.balanceOf(eulerAccount));
            if (maxWithdraw < outLimit) outLimit = maxWithdraw;
        }

        return (inLimit, outLimit);
    }

    function decodeCap(uint256 amountCap) internal pure returns (uint256) {
        if (amountCap == 0) return type(uint256).max;

        unchecked {
            // Cannot overflow because this is less than 2**256:
            //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }
}
