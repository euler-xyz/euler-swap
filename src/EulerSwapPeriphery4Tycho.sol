// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwapPeriphery} from "./interfaces/IEulerSwapPeriphery.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {EulerSwapPeriphery} from "./EulerSwapPeriphery.sol";


contract EulerSwapPeriphery4Tycho is EulerSwapPeriphery {
    function quoteExactInputWithReserves(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint112 reserve0, uint112 reserve1)
        external
        view
        returns (uint256)
    {
        return computeQuoteWithReserves(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, true, reserve0, reserve1);
    }

    function quoteExactOutputWithReserves(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut, uint112 reserve0, uint112 reserve1)
        external
        view
        returns (uint256)
    {
        return computeQuoteWithReserves(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountOut, false, reserve0, reserve1);
    }


    /// @dev Computes the quote for a swap by applying fees and validating state conditions. Starting with provided reserves
    /// @param eulerSwap The EulerSwap contract to quote from
    /// @param tokenIn The input token address
    /// @param tokenOut The output token address
    /// @param amount The amount to quote (input amount if exactIn=true, output amount if exactIn=false)
    /// @param exactIn True if quoting for exact input amount, false if quoting for exact output amount
    /// @param reserve0 Starting reserve in token0
    /// @param reserve1 Starting reserve in token1
    /// @return The quoted amount (output amount if exactIn=true, input amount if exactIn=false)
    /// @dev Validates:
    ///      - EulerSwap operator is installed
    ///      - Token pair is supported
    ///      - Sufficient reserves exist
    ///      - Sufficient cash is available
    function computeQuoteWithReserves(IEulerSwap eulerSwap, address tokenIn, address tokenOut, uint256 amount, bool exactIn, uint112 reserve0, uint112 reserve1)
        internal
        view
        returns (uint256)
    {
        require(
            IEVC(eulerSwap.EVC()).isAccountOperatorAuthorized(eulerSwap.eulerAccount(), address(eulerSwap)),
            OperatorNotInstalled()
        );
        require(amount <= type(uint112).max, SwapLimitExceeded());

        uint256 feeMultiplier = eulerSwap.feeMultiplier();

        // exactIn: decrease received amountIn, rounding down
        if (exactIn) amount = amount * feeMultiplier / 1e18;

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

        // exactOut: increase required quote(amountIn), rounding up
        if (!exactIn) quote = (quote * 1e18 + (feeMultiplier - 1)) / feeMultiplier;

        return quote;
    }
}
