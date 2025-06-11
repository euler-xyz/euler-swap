// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IEulerSwapHookTarget {
    function beforeSwap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 amountOut,
        address msgSender,
        address to,
        uint112 reserve0,
        uint112 reserve1
    ) external returns (uint64 fee);

    function afterSwap(
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 fee0,
        uint256 fee1,
        address msgSender,
        address to,
        uint112 reserve0,
        uint112 reserve1
    ) external;
}
