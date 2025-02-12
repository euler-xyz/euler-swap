// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IMaglevPeriphery {
    /// @notice How much `tokenOut` can I get for `amountIn` of `tokenIn`?
    function quoteExactInput(address maglev, address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);

    /// @notice How much `tokenIn` do I need to get `amountOut` of `tokenOut`?
    function quoteExactOutput(address maglev, address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256);
}
