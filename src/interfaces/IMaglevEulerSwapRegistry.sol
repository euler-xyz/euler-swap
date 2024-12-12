// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IMaglevEulerSwapRegistry {
    function registerPool(address _pool) external;

    function getPool(address _assetA, address _assetB, uint256 _fee) external view returns (address);
}
