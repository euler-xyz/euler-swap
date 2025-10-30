// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IEulerSwapCallee {
    /// @notice If non-empty data is provided to `swap()`, then this callback function
    /// is invoked on the `to` address, allowing flash-swaps (withdrawing output before
    /// sending input.
    /// @dev This callback mechanism is designed to be as similar as possible to Uniswap2.
    /// @param sender The address that originated the swap
    /// @param amount0 The requested output amount of token0
    /// @param amount1 The requested output amount of token1
    /// @param data Opaque callback data passed by swapper
    function eulerSwapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
