// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwapPeriphery} from "./interfaces/IEulerSwapPeriphery.sol";
import {IERC20, IEulerSwap, SafeERC20} from "./EulerSwap.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapPeriphery is IEulerSwapPeriphery {
    using SafeERC20 for IERC20;

    error UnsupportedPair();
    error OperatorNotInstalled();
    error InsufficientReserves();
    error InsufficientCash();
    error AmountOutLessThanMin();
    error AmountInMoreThanMax();

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactIn(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external {
        uint256 amountOut = computeQuote(
            IEulerSwap(eulerSwap),
            tokenIn,
            tokenOut,
            amountIn,
            true
        );

        require(amountOut >= amountOutMin, AmountOutLessThanMin());

        swap(eulerSwap, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactOut(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax
    ) external {
        uint256 amountIn = computeQuote(
            IEulerSwap(eulerSwap),
            tokenIn,
            tokenOut,
            amountOut,
            false
        );

        require(amountIn <= amountInMax, AmountInMoreThanMax());

        swap(eulerSwap, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactInput(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256) {
        return
            computeQuote(
                IEulerSwap(eulerSwap),
                tokenIn,
                tokenOut,
                amountIn,
                true
            );
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactOutput(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256) {
        return
            computeQuote(
                IEulerSwap(eulerSwap),
                tokenIn,
                tokenOut,
                amountOut,
                false
            );
    }

    
    function quoteExactInputExplicit(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256) {
        return
            computeQuoteExplicit(
                IEulerSwap(eulerSwap),
                tokenIn,
                tokenOut,
                amountIn,
                true
            );
    }

    
    function quoteExactOutputExplicit(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256) {
        return
            computeQuoteExplicit(
                IEulerSwap(eulerSwap),
                tokenIn,
                tokenOut,
                amountOut,
                false
            );
    }

    /// @dev Internal function to execute a token swap through EulerSwap
    /// @param eulerSwap The EulerSwap contract address to execute the swap through
    /// @param tokenIn The address of the input token being swapped
    /// @param tokenOut The address of the output token being received
    /// @param amountIn The amount of input tokens to swap
    /// @param amountOut The amount of output tokens to receive
    function swap(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        IERC20(tokenIn).safeTransferFrom(msg.sender, eulerSwap, amountIn);

        bool isAsset0In = tokenIn < tokenOut;
        (isAsset0In)
            ? IEulerSwap(eulerSwap).swap(0, amountOut, msg.sender, "")
            : IEulerSwap(eulerSwap).swap(amountOut, 0, msg.sender, "");
    }

    /// @dev Computes the quote for a swap by applying fees and validating state conditions
    /// @param eulerSwap The EulerSwap contract to quote from
    /// @param tokenIn The input token address
    /// @param tokenOut The output token address
    /// @param amount The amount to quote (input amount if exactIn=true, output amount if exactIn=false)
    /// @param exactIn True if quoting for exact input amount, false if quoting for exact output amount
    /// @return The quoted amount (output amount if exactIn=true, input amount if exactIn=false)
    /// @dev Validates:
    ///      - EulerSwap operator is installed
    ///      - Token pair is supported
    ///      - Sufficient reserves exist
    ///      - Sufficient cash is available
    function computeQuote(
        IEulerSwap eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool exactIn
    ) internal view returns (uint256) {
        require(
            IEVC(eulerSwap.EVC()).isAccountOperatorAuthorized(
                eulerSwap.eulerAccount(),
                address(eulerSwap)
            ),
            OperatorNotInstalled()
        );

        uint256 feeMultiplier = eulerSwap.feeMultiplier();
        address vault0 = eulerSwap.vault0();
        address vault1 = eulerSwap.vault1();
        (uint112 reserve0, uint112 reserve1, ) = eulerSwap.getReserves();

        // exactIn: decrease received amountIn, rounding down
        if (exactIn) amount = (amount * feeMultiplier) / 1e18;

        bool asset0IsInput;
        {
            address asset0 = eulerSwap.asset0();
            address asset1 = eulerSwap.asset1();

            if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
            else if (tokenIn == asset1 && tokenOut == asset0)
                asset0IsInput = false;
            else revert UnsupportedPair();
        }

        uint256 quote = binarySearch(
            eulerSwap,
            reserve0,
            reserve1,
            amount,
            exactIn,
            asset0IsInput
        );

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(
                quote <= (asset0IsInput ? reserve1 : reserve0),
                InsufficientReserves()
            );
            require(
                quote <= IEVault(asset0IsInput ? vault1 : vault0).cash(),
                InsufficientCash()
            );
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(
                amount <= (asset0IsInput ? reserve1 : reserve0),
                InsufficientReserves()
            );
            require(
                amount <= IEVault(asset0IsInput ? vault1 : vault0).cash(),
                InsufficientCash()
            );
        }

        // exactOut: increase required quote(amountIn), rounding up
        if (!exactIn)
            quote = (quote * 1e18 + (feeMultiplier - 1)) / feeMultiplier;

        return quote;
    }

    /// @dev Computes the quote for a swap by applying fees and validating state conditions
    /// @param eulerSwap The EulerSwap contract to quote from
    /// @param tokenIn The input token address
    /// @param tokenOut The output token address
    /// @param amount The amount to quote (input amount if exactIn=true, output amount if exactIn=false)
    /// @param exactIn True if quoting for exact input amount, false if quoting for exact output amount
    /// @return The quoted amount (output amount if exactIn=true, input amount if exactIn=false)
    /// @dev Validates:
    ///      - EulerSwap operator is installed
    ///      - Token pair is supported
    ///      - Sufficient reserves exist
    ///      - Sufficient cash is available
    function computeQuoteExplicit(
        IEulerSwap eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool exactIn
    ) internal view returns (uint256) {
        require(
            IEVC(eulerSwap.EVC()).isAccountOperatorAuthorized(
                eulerSwap.eulerAccount(),
                address(eulerSwap)
            ),
            OperatorNotInstalled()
        );

        uint256 feeMultiplier = eulerSwap.feeMultiplier();
        address vault0 = eulerSwap.vault0();
        address vault1 = eulerSwap.vault1();
        (uint112 reserve0, uint112 reserve1, ) = eulerSwap.getReserves();

        // exactIn: decrease received amountIn, rounding down
        if (exactIn) amount = (amount * feeMultiplier) / 1e18;

        bool asset0IsInput;
        {
            address asset0 = eulerSwap.asset0();
            address asset1 = eulerSwap.asset1();

            if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
            else if (tokenIn == asset1 && tokenOut == asset0)
                asset0IsInput = false;
            else revert UnsupportedPair();
        }

        uint256 quote = quoteExplicit(
            eulerSwap,
            reserve0,
            reserve1,
            amount,
            exactIn,
            asset0IsInput
        );

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(
                quote <= (asset0IsInput ? reserve1 : reserve0),
                InsufficientReserves()
            );
            require(
                quote <= IEVault(asset0IsInput ? vault1 : vault0).cash(),
                InsufficientCash()
            );
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(
                amount <= (asset0IsInput ? reserve1 : reserve0),
                InsufficientReserves()
            );
            require(
                amount <= IEVault(asset0IsInput ? vault1 : vault0).cash(),
                InsufficientCash()
            );
        }

        // exactOut: increase required quote(amountIn), rounding up
        if (!exactIn)
            quote = (quote * 1e18 + (feeMultiplier - 1)) / feeMultiplier;

        return quote;
    }

    /// @notice Binary searches for the output amount along a swap curve given input parameters
    /// @dev General-purpose routine for binary searching swapping curves.
    /// Although some curves may have more efficient closed-form solutions,
    /// this works with any monotonic curve.
    /// @param eulerSwap The EulerSwap contract to search the curve for
    /// @param reserve0 Current reserve of asset0 in the pool
    /// @param reserve1 Current reserve of asset1 in the pool
    /// @param amount The input or output amount depending on exactIn
    /// @param exactIn True if amount is input amount, false if amount is output amount
    /// @param asset0IsInput True if asset0 is being input, false if asset1 is being input
    /// @return output The calculated output amount from the binary search
    function binarySearch(
        IEulerSwap eulerSwap,
        uint112 reserve0,
        uint112 reserve1,
        uint256 amount,
        bool exactIn,
        bool asset0IsInput
    ) internal view returns (uint256 output) {
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

            uint256 low;
            uint256 high = type(uint112).max;

            while (low < high) {
                uint256 mid = (low + high) / 2;
                if (
                    dy == 0
                        ? eulerSwap.verify(uint256(reserve0New), mid)
                        : eulerSwap.verify(mid, uint256(reserve1New))
                ) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }

            if (dx != 0) dy = int256(low) - reserve1New;
            else dx = int256(low) - reserve0New;
        }

        if (exactIn) {
            if (asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
        } else {
            if (asset0IsInput) output = uint256(dx);
            else output = uint256(dy);
        }
    }

    /// @notice Quoted amount is the amount of assets to buy from the AMM
    /// @param eulerSwap The EulerSwap contract to search the curve for
    /// @param reserve0 Current reserve of asset0 in the pool
    /// @param reserve1 Current reserve of asset1 in the pool
    /// @param amount The input or output amount depending on exactIn
    /// @param exactIn True if amount is input amount, false if amount is output amount
    /// @param asset0IsInput True if asset0 is being input, false if asset1 is being input
    /// @return output The calculated output amount from the binary search
    function quoteExplicit(
        IEulerSwap eulerSwap,
        uint112 reserve0,
        uint112 reserve1,
        uint256 amount,
        bool exactIn,
        bool asset0IsInput
    ) internal view returns (uint256 output) {
        uint256 px = asset0IsInput ? eulerSwap.priceX() : eulerSwap.priceY();
        uint256 py = asset0IsInput ? eulerSwap.priceY() : eulerSwap.priceX();
        uint256 x0 = asset0IsInput ? eulerSwap.initialReserve0() : eulerSwap.initialReserve1();
        uint256 y0 = asset0IsInput ? eulerSwap.initialReserve1() : eulerSwap.initialReserve0();
        uint256 cx = asset0IsInput ? eulerSwap.concentrationX() : eulerSwap.concentrationY();
        uint256 cy = asset0IsInput ? eulerSwap.concentrationY() : eulerSwap.concentrationX();

        if (exactIn) {
            if (reserve0 < x0) {
                // Left side, moving towards center
                if (reserve0 + amount < x0){
                    // Finish left of center
                    output = reserve1 - fInternal(reserve0 + amount, px, py, x0, y0, cx);
                } else {
                    // Cross center to right side
                    output = reserve1 - fInverseInternal(reserve0 + amount, px, py, x0, y0, cy);
                }
            } else {
                // Right side, moving away from center
                output = reserve1 - fInverseInternal(reserve0 + amount, px, py, x0, y0, cy);
            }
        } else {
            if (reserve0 < x0) {
                // Left side, moving towards center
                if (reserve1 - amount > y0){
                    // Finish left of center
                    output = fInverseInternal(reserve1 - amount, px, py, x0, y0, cx) - reserve0;
                } else {
                    // Cross center to right side
                    output = fInternal(reserve1 - amount, py, px, y0, x0, cy) - reserve0;
                }
            } else {
                // Right side, moving away from center
                output = fInternal(reserve1 - amount, py, px, y0, x0, cy) - reserve0;
            }
        }

        return output;
    }

    /// @dev EulerSwap curve definition
    /// Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function fInternal(
        uint256 x,
        uint256 px,
        uint256 py,
        uint256 x0,
        uint256 y0,
        uint256 c
    ) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(
                px * (x0 - x),
                c * x + (1e18 - c) * x0,
                x * 1e18,
                Math.Rounding.Ceil
            );
            require(v <= type(uint248).max, AmountOutLessThanMin());
            return y0 + (v + (py - 1)) / py;
        }
    }

    function fInverseInternal(
        uint256 y,
        uint256 px,
        uint256 py,
        uint256 x0,
        uint256 y0,
        uint256 c
    ) internal pure returns (uint256) {
        unchecked {
            // A component of the quadratic formula: a = 2 * c
            uint256 A = 2 * c;

            // B component of the quadratic formula
            int256 B = int256((px * (y - y0) + py - 1) / py) -
                int256((x0 * (2 * c - 1e18) + 1e18 - 1) / 1e18);

            // B^2 component, using FullMath for overflow safety
            uint256 absB = B < 0 ? uint256(-B) : uint256(B);
            uint256 squaredB = Math.mulDiv(
                absB,
                absB,
                1e18,
                Math.Rounding.Ceil
            );

            // 4 * A * C component of the quadratic formula
            uint256 AC4 = Math.mulDiv(
                Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil),
                Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil),
                1e18,
                Math.Rounding.Ceil
            );

            // Discriminant: b^2 + 4ac, scaled up to maintain precision
            uint256 discriminant = (squaredB + AC4) * 1e18;

            // Square root of the discriminant (rounded up)
            uint256 sqrt = Math.sqrt(discriminant);
            sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;

            // Compute and return x = fInverse(y) using the quadratic formula
            return
                Math.mulDiv(
                    uint256(int256(sqrt) - B),
                    1e18,
                    A,
                    Math.Rounding.Ceil
                );
        }
    }

    /**
     * @notice Computes the inverse of the `f()` function for the EulerSwap liquidity curve.
     * @dev Solves for `x` given `y` using the quadratic formula derived from the liquidity curve:
     *      x = (-b + sqrt(b^2 + 4ac)) / 2a
     *      Utilises mulDiv to avoid overflow and ensures precision with upward rounding.
     *
     * @param y The y-coordinate input value (must be greater than `y0`).
     * @param px Price factor for the x-axis (scaled by 1e18, between 1e18 and 1e36).
     * @param py Price factor for the y-axis (scaled by 1e18, between 1e18 and 1e36).
     * @param x0 Reference x-value on the liquidity curve (≤ 2^112 - 1).
     * @param y0 Reference y-value on the liquidity curve (≤ 2^112 - 1).
     * @param c Curve parameter shaping liquidity concentration (scaled by 1e18, between 0 and 1e18).
     *
     * @return x The computed x-coordinate on the liquidity curve.
     *
     * @custom:precision Uses rounding up to maintain precision in all calculations.
     * @custom:safety FullMath handles potential overflow in the b^2 computation.
     * @custom:requirement Input `y` must be strictly greater than `y0`; otherwise, the function will revert.
     */
    function fInverse(
        uint256 y,
        uint256 px,
        uint256 py,
        uint256 x0,
        uint256 y0,
        uint256 c
    ) external pure returns (uint256) {
        unchecked {
            // A component of the quadratic formula: a = 2 * c
            uint256 A = 2 * c;

            // B component of the quadratic formula
            int256 B = int256((px * (y - y0) + py - 1) / py) -
                int256((x0 * (2 * c - 1e18) + 1e18 - 1) / 1e18);

            // B^2 component, using FullMath for overflow safety
            uint256 absB = B < 0 ? uint256(-B) : uint256(B);
            uint256 squaredB = Math.mulDiv(
                absB,
                absB,
                1e18,
                Math.Rounding.Ceil
            );

            // 4 * A * C component of the quadratic formula
            uint256 AC4 = Math.mulDiv(
                Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil),
                Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil),
                1e18,
                Math.Rounding.Ceil
            );

            // Discriminant: b^2 + 4ac, scaled up to maintain precision
            uint256 discriminant = (squaredB + AC4) * 1e18;

            // Square root of the discriminant (rounded up)
            uint256 sqrt = Math.sqrt(discriminant);
            sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;

            // Compute and return x = fInverse(y) using the quadratic formula
            return
                Math.mulDiv(
                    uint256(int256(sqrt) - B),
                    1e18,
                    A,
                    Math.Rounding.Ceil
                );
        }
    }
}
