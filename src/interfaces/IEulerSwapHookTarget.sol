// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

uint8 constant EULER_SWAP_HOOK_BEFORE_SWAP = 1 << 0;
uint8 constant EULER_SWAP_HOOK_GET_FEE = 1 << 1;
uint8 constant EULER_SWAP_HOOK_AFTER_SWAP = 1 << 2;

interface IEulerSwapHookTarget {
    function beforeSwap(uint256 amount0Out, uint256 amount1Out, address msgSender, address to) external;

    function getFee(bool asset0IsInput, uint112 reserve0, uint112 reserve1, bool readOnly)
        external
        returns (uint64 fee);

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
