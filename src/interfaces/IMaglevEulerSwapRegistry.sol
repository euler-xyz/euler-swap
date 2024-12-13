// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IMaglevEulerSwapRegistry {
    function registerPool(address _pool) external;

    function getPool(address _assetA, address _assetB, uint256 _fee) external view returns (address);
    function allPools(uint256 _index) external view returns (address);
    function allPoolsLength() external view returns (uint256);
    function getAllPoolsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory);
}
