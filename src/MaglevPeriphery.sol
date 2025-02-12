// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IMaglev} from "./interfaces/IMaglev.sol";

contract MaglevPeriphery {
    address private immutable evc;

    constructor(address evc_) {
        evc = evc_;
    }

    error UnsupportedCurve();
    error UnsupportedPair();
    error OperatorNotInstalled();
    error InsufficientReserves();
    error InsufficientCash();

    /// @notice How much `tokenOut` can I get for `amountIn` of `tokenIn`?
    function quoteExactInput(address maglev, address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256) {
        return computeFullQuote(IMaglev(maglev), tokenIn, tokenOut, amountIn, true);
    }

    /// @notice How much `tokenIn` do I need to get `amountOut` of `tokenOut`?
    function quoteExactOutput(address maglev, address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256) {
        return computeFullQuote(IMaglev(maglev), tokenIn, tokenOut, amountOut, false);
    }

    /// @dev This function handles quoting, including swap fees. Curve-specific
    /// quote calculations are delegated to computeQuote().
    function computeFullQuote(IMaglev maglev, address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        internal
        view
        returns (uint256)
    {
        require(maglev.curve() == keccak256("EulerSwap v1"), UnsupportedCurve());
        require(IEVC(evc).isAccountOperatorAuthorized(maglev.myAccount(), address(maglev)), OperatorNotInstalled());

        uint256 feeMultiplier = maglev.feeMultiplier();
        address vault0 = maglev.vault0();
        address vault1 = maglev.vault1();
        (uint112 reserve0, uint112 reserve1,) = maglev.getReserves();

        // exactIn: decrease received amountIn, rounding down
        if (exactIn) amount = amount * feeMultiplier / 1e18;

        bool asset0IsInput;
        {
            address asset0 = maglev.asset0();
            address asset1 = maglev.asset1();

            if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
            else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
            else revert UnsupportedPair();
        }

        uint256 quote = computeQuote(maglev, reserve0, reserve1, amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(quote <= (asset0IsInput ? reserve1 : reserve0), InsufficientReserves());
            require(quote <= IEVault(asset0IsInput ? vault1 : vault0).cash(), InsufficientCash());
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(amount <= (asset0IsInput ? reserve1 : reserve0), InsufficientReserves());
            require(amount <= IEVault(asset0IsInput ? vault1 : vault0).cash(), InsufficientCash());
        }

        // exactOut: increase required quote(amountIn), rounding up
        if (!exactIn) quote = (quote * 1e18 + (feeMultiplier - 1)) / feeMultiplier;

        return quote;
    }

    /// @dev This function generates quotes given the specific installed curve
    /// instance. The base-class implementation is a binary search, however this
    /// may be overridden by a subclass if there is a more efficient method
    /// of computing quotes, or if a curve is non-convex.
    function computeQuote(IMaglev maglev, uint112 reserve0, uint112 reserve1, uint256 amount, bool exactIn, bool asset0IsInput)
        internal
        view
        returns (uint256 output)
    {
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
                if (dy == 0 ? maglev.verify(uint256(reserve0New), mid) : maglev.verify(mid, uint256(reserve1New))) high = mid;
                else low = mid + 1;
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
}
