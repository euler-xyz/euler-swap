// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";

contract MinimalRouter is SafeCallback {
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    constructor(IPoolManager _manager) SafeCallback(_manager) {}

    /// @dev an unsafe swap function that does not check for slippage
    /// @param key The pool key
    /// @param zeroForOne The direction of the swap
    /// @param amountIn The amount of input token, should be provided (as an estimate) for exact output swaps
    /// @param amountOut The amount of output token can be provided as 0, for exact input swaps
    /// @param hookData The data to pass to the hook
    function swap(PoolKey memory key, bool zeroForOne, uint256 amountIn, uint256 amountOut, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            poolManager.unlock(abi.encode(msg.sender, key, zeroForOne, amountIn, amountOut, hookData)), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, ethBalance);
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (
            address sender,
            PoolKey memory key,
            bool zeroForOne,
            uint256 amountIn,
            uint256 amountOut,
            bytes memory hookData
        ) = abi.decode(data, (address, PoolKey, bool, uint256, uint256, bytes));

        // send the input first to avoid PoolManager token balance issues
        zeroForOne
            ? key.currency0.settle(poolManager, sender, amountIn, false)
            : key.currency1.settle(poolManager, sender, amountIn, false);

        // execute the swap
        poolManager.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountOut != 0 ? int256(amountOut) : -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            hookData
        );

        // observe deltas
        int256 delta0 = poolManager.currencyDelta(address(this), key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), key.currency1);

        // take the output
        if (delta0 > 0) key.currency0.take(poolManager, sender, uint256(delta0), false);
        if (delta1 > 0) key.currency1.take(poolManager, sender, uint256(delta1), false);

        // account for prepaid input against the observed deltas
        BalanceDelta returnDelta = toBalanceDelta(int128(delta0), int128(delta1))
            + toBalanceDelta(
                zeroForOne ? -int128(int256(amountIn)) : int128(0), zeroForOne ? int128(0) : -int128(int256(amountIn))
            );

        return abi.encode(returnDelta);
    }
}
