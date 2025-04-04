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
    error SwapLimitExceeded();
    error AmountOutLessThanMin();
    error AmountInMoreThanMax();

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactIn(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        external
    {
        uint256 amountOut = computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, true);

        require(amountOut >= amountOutMin, AmountOutLessThanMin());

        swap(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactOut(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMax)
        external
    {
        uint256 amountIn = computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountOut, false);

        require(amountIn <= amountInMax, AmountInMoreThanMax());

        swap(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256)
    {
        return computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, true);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut)
        external
        view
        returns (uint256)
    {
        return computeQuote(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountOut, false);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function getLimits(address eulerSwap, address tokenIn, address tokenOut) external view returns (uint256, uint256) {
        if (
            !IEVC(IEulerSwap(eulerSwap).EVC()).isAccountOperatorAuthorized(
                IEulerSwap(eulerSwap).eulerAccount(), eulerSwap
            )
        ) return (0, 0);

        return calcLimits(IEulerSwap(eulerSwap), checkTokens(IEulerSwap(eulerSwap), tokenIn, tokenOut));
    }

    /// @dev Internal function to execute a token swap through EulerSwap
    /// @param eulerSwap The EulerSwap contract address to execute the swap through
    /// @param tokenIn The address of the input token being swapped
    /// @param tokenOut The address of the output token being received
    /// @param amountIn The amount of input tokens to swap
    /// @param amountOut The amount of output tokens to receive
    function swap(IEulerSwap eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
        internal
    {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(eulerSwap), amountIn);

        bool isAsset0In = tokenIn < tokenOut;
        (isAsset0In) ? eulerSwap.swap(0, amountOut, msg.sender, "") : eulerSwap.swap(amountOut, 0, msg.sender, "");
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
    function computeQuote(IEulerSwap eulerSwap, address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        internal
        view
        returns (uint256)
    {
        require(
            IEVC(eulerSwap.EVC()).isAccountOperatorAuthorized(eulerSwap.eulerAccount(), address(eulerSwap)),
            OperatorNotInstalled()
        );
        require(amount <= type(uint112).max, SwapLimitExceeded());

        uint256 fee = eulerSwap.fee();
        (uint112 reserve0, uint112 reserve1,) = eulerSwap.getReserves();

        // exactIn: decrease effective amountIn
        if (exactIn) amount = amount - (amount * fee / 1e18);

        bool asset0IsInput = checkTokens(eulerSwap, tokenIn, tokenOut);
        (uint256 inLimit, uint256 outLimit) = calcLimits(eulerSwap, asset0IsInput);

        uint256 quote = binarySearch(eulerSwap, reserve0, reserve1, amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(amount <= inLimit && quote <= outLimit, SwapLimitExceeded());
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(amount <= outLimit && quote <= inLimit, SwapLimitExceeded());
        }

        // exactOut: inflate required amountIn
        if (!exactIn) quote = (quote * 1e18) / (1e18 - fee);

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
            require(reserve0New > 0 && reserve1New > 0, SwapLimitExceeded());

            uint256 low;
            uint256 high = type(uint112).max;

            while (low < high) {
                uint256 mid = (low + high) / 2;
                require(mid > 0, SwapLimitExceeded());
                (uint256 a, uint256 b) = dy == 0 ? (uint256(reserve0New), mid) : (mid, uint256(reserve1New));
                if (eulerSwap.verify(a, b)) {
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

    /**
     * @notice Calculates the maximum input and output amounts for a swap based on protocol constraints
     * @dev Determines limits by checking multiple factors:
     *      1. Supply caps and existing debt for the input token
     *      2. Available reserves in the EulerSwap for the output token
     *      3. Available cash and borrow caps for the output token
     *      4. Account balances in the respective vaults
     *
     * @param es The EulerSwap contract to calculate limits for
     * @param asset0IsInput Boolean indicating whether asset0 (true) or asset1 (false) is the input token
     * @return uint256 Maximum amount of input token that can be deposited
     * @return uint256 Maximum amount of output token that can be withdrawn
     */
    function calcLimits(IEulerSwap es, bool asset0IsInput) internal view returns (uint256, uint256) {
        uint256 inLimit = type(uint112).max;
        uint256 outLimit = type(uint112).max;

        address eulerAccount = es.eulerAccount();
        (IEVault vault0, IEVault vault1) = (IEVault(es.vault0()), IEVault(es.vault1()));
        // Supply caps on input
        {
            IEVault vault = (asset0IsInput ? vault0 : vault1);
            uint256 maxDeposit = vault.debtOf(eulerAccount) + vault.maxDeposit(eulerAccount);
            if (maxDeposit < inLimit) inLimit = maxDeposit;
        }

        // Remaining reserves of output
        {
            (uint112 reserve0, uint112 reserve1,) = es.getReserves();
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

    /**
     * @notice Decodes a compact-format cap value to its actual numerical value
     * @dev The cap uses a compact-format where:
     *      - If amountCap == 0, there's no cap (returns max uint256)
     *      - Otherwise, the lower 6 bits represent the exponent (10^exp)
     *      - The upper bits (>> 6) represent the mantissa
     *      - The formula is: (10^exponent * mantissa) / 100
     * @param amountCap The compact-format cap value to decode
     * @return The actual numerical cap value (type(uint256).max if uncapped)
     * @custom:security Uses unchecked math for gas optimization as calculations cannot overflow:
     *                  maximum possible value 10^(2^6-1) * (2^10-1) ≈ 1.023e+66 < 2^256
     */
    function decodeCap(uint256 amountCap) internal pure returns (uint256) {
        if (amountCap == 0) return type(uint256).max;

        unchecked {
            // Cannot overflow because this is less than 2**256:
            //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }

    /**
     * @notice Verifies that the given tokens are supported by the EulerSwap pool and determines swap direction
     * @dev Returns a boolean indicating whether the input token is asset0 (true) or asset1 (false)
     * @param eulerSwap The EulerSwap pool contract to check against
     * @param tokenIn The input token address for the swap
     * @param tokenOut The output token address for the swap
     * @return asset0IsInput True if tokenIn is asset0 and tokenOut is asset1, false if reversed
     * @custom:error UnsupportedPair Thrown if the token pair is not supported by the EulerSwap pool
     */
    function checkTokens(IEulerSwap eulerSwap, address tokenIn, address tokenOut)
        internal
        view
        returns (bool asset0IsInput)
    {
        address asset0 = eulerSwap.asset0();
        address asset1 = eulerSwap.asset1();

        if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
        else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
        else revert UnsupportedPair();
    }
}
