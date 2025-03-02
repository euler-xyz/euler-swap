// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {console} from "forge-std/Test.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {IEulerSwapPeriphery} from "./interfaces/IEulerSwapPeriphery.sol";

contract EulerSwapPeriphery is IEulerSwapPeriphery {
    address private immutable evc;

    constructor(address evc_) {
        evc = evc_;
    }

    error UnsupportedPair();
    error OperatorNotInstalled();
    error InsufficientReserves();
    error InsufficientCash();

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

    /// @dev High-level quoting function. It handles fees and performs
    /// state validation, for example that there is sufficient cash available.
    function computeQuote(IEulerSwap eulerSwap, address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        internal
        view
        returns (uint256)
    {
        require(
            IEVC(evc).isAccountOperatorAuthorized(eulerSwap.myAccount(), address(eulerSwap)), OperatorNotInstalled()
        );

        uint256 feeMultiplier = eulerSwap.feeMultiplier();
        address vault0 = eulerSwap.vault0();
        address vault1 = eulerSwap.vault1();
        (uint112 reserve0, uint112 reserve1,) = eulerSwap.getReserves();

        // exactIn: decrease received amountIn, rounding down
        if (exactIn) amount = amount * feeMultiplier / 1e18;

        bool asset0IsInput;
        {
            address asset0 = eulerSwap.asset0();
            address asset1 = eulerSwap.asset1();

            if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
            else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
            else revert UnsupportedPair();
        }

        uint256 quote = binarySearch(eulerSwap, reserve0, reserve1, amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            console.log("Q",quote);
            console.log("R",(asset0IsInput ? reserve1 : reserve0));
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

    /// @dev General-purpose routine for binary searching swapping curves.
    /// Although some curves may have more efficient closed-form solutions,
    /// this works with any monotonic curve.
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
                if (dy == 0 ? eulerSwap.verify(uint256(reserve0New), mid) : eulerSwap.verify(mid, uint256(reserve1New)))
                {
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
}
