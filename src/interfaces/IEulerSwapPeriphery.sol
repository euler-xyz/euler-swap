// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IEulerSwapPeriphery {
    /// @notice Swap `amountIn` of `tokenIn` for `tokenOut`, with at least `amountOutMin` received.
    function swapExactIn(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        external;

    /// @notice Swap `amountOut` of `tokenOut` for `tokenIn`, with at most `amountInMax` paid.
    function swapExactOut(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMax)
        external;

    /// @notice How much `tokenOut` can I get for `amountIn` of `tokenIn`?
    function quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn)
        external
        
        returns (uint256);

    /// @notice How much `tokenIn` do I need to get `amountOut` of `tokenOut`?
    function quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut)
        external
        
        returns (uint256);
}
