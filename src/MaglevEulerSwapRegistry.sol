// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IMaglevEulerSwap} from "./interfaces/IMaglevEulerSwap.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/// @title MaglevEulerSwapRegistry contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract MaglevEulerSwapRegistry is Ownable {
    event PoolRegistered(address indexed asset0, address indexed asset1, uint256 indexed fee, address pool);

    error InvalidQuery();
    error PoolAlreadyRegistered();

    /// @dev An array to store all pools addresses.
    address[] public allPools;
    /// @dev Mapping from asset0/asset1/fee => pool address.
    mapping(address => mapping(address => mapping(uint256 => address))) public getPool;

    constructor() Ownable(msg.sender) {}

    /// @notice Register a deployed pool address.
    /// @param _pool Pool's address.
    function registerPool(address _pool) external onlyOwner {
        address asset0 = IMaglevEulerSwap(_pool).asset0();
        address asset1 = IMaglevEulerSwap(_pool).asset1();
        uint256 fee = IMaglevEulerSwap(_pool).fee();

        require(getPool[asset0][asset1][fee] == address(0), PoolAlreadyRegistered());

        getPool[asset0][asset1][fee] = _pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[asset1][asset0][fee] = _pool;

        allPools.push(_pool);

        emit PoolRegistered(asset0, asset1, fee, _pool);
    }

    /// @notice Get the length of `allPools` array.
    /// @return `allPools` length.
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice Get a slice of the registered pools array.
    /// @param _start Start index of the slice.
    /// @param _end End index of the slice.
    /// @return An array containing the slice of the registered pools.
    function getAllPoolsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = allPools.length;
        if (_end == type(uint256).max) _end = length;
        if (_end < _start || _end > length) revert InvalidQuery();

        address[] memory allPoolsList = new address[](_end - _start);
        for (uint256 i; i < _end - _start; ++i) {
            allPoolsList[i] = allPools[_start + i];
        }

        return allPoolsList;
    }
}
