// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IMaglev {
    function activate() external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function verify(uint256 newReserve0, uint256 newReserve1) external view returns (bool);

    function curve() external view returns (bytes32);
    function vault0() external view returns (address);
    function vault1() external view returns (address);
    function asset0() external view returns (address);
    function asset1() external view returns (address);
    function myAccount() external view returns (address);
    function feeMultiplier() external view returns (uint256);
    function initialReserve0() external view returns (uint112);
    function initialReserve1() external view returns (uint112);
    function getReserves() external view returns (uint112, uint112, uint32);

    function priceX() external view returns (uint256);
    function priceY() external view returns (uint256);
    function concentrationX() external view returns (uint256);
    function concentrationY() external view returns (uint256);
}
