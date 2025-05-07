// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwapPeriphery} from "./interfaces/IEulerSwapPeriphery.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {EulerSwapPeriphery} from "./EulerSwapPeriphery.sol";
import {CtxLib} from "./libraries/CtxLib.sol";
import {QuoteLib} from "./libraries/QuoteLib.sol";

contract EulerSwapPeriphery4Tycho is EulerSwapPeriphery {
    address public immutable evc;

    constructor(address _evc) {
        evc = _evc;
    }

    function quoteExactInputWithReserves(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint112 reserve0, uint112 reserve1)
        external
        returns (uint256)
    {
        return computeQuoteWithReserves(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, true, reserve0, reserve1);
    }

    function quoteExactOutputWithReserves(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut, uint112 reserve0, uint112 reserve1)
        external
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
        returns (uint256)
    {
        // make a copy of the pools storage with provided reserves to be able to use the QuoteLib in the periphery
        IEulerSwap.Params memory p = eulerSwap.getParams();
        CtxLib.Storage storage s = CtxLib.getStorage();
        s.reserve0 = reserve0;
        s.reserve1 = reserve1;
        s.status = 1;

        return PeripheryQuoteLib.computeQuote(evc, p, QuoteLib.checkTokens(p, tokenIn, tokenOut), amount, exactIn, address(eulerSwap));
    }
}


library PeripheryQuoteLib {

    // Function copied from QuoteLib, with modified check of account operator. The quote is run by periphery, not the pool, so the check must
    // be modified to pass `eulerSwap` not `address(this)`
    function computeQuote(address evc, IEulerSwap.Params memory p, bool asset0IsInput, uint256 amount, bool exactIn, address eulerSwap)
        internal
        view
        returns (uint256)
    {
        if (amount == 0) return 0;

        // modified check, passing `eulerSwap` instead of `address(this)`
        require(IEVC(evc).isAccountOperatorAuthorized(p.eulerAccount, eulerSwap), QuoteLib.OperatorNotInstalled());
        require(amount <= type(uint112).max, QuoteLib.SwapLimitExceeded());

        uint256 fee = p.fee;

        // exactIn: decrease effective amountIn
        if (exactIn) amount = amount - (amount * fee / 1e18);

        (uint256 inLimit, uint256 outLimit) = QuoteLib.calcLimits(p, asset0IsInput);

        uint256 quote = QuoteLib.findCurvePoint(p, amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(amount <= inLimit && quote <= outLimit, QuoteLib.SwapLimitExceeded());
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(amount <= outLimit && quote <= inLimit, QuoteLib.SwapLimitExceeded());
        }

        // exactOut: inflate required amountIn
        if (!exactIn) quote = (quote * 1e18) / (1e18 - fee);

        return quote;
    }
}