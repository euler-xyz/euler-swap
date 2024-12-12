// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IMaglevEulerSwap} from "./interfaces/IMaglevEulerSwap.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

/// @title MaglevEulerSwapRegistry contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract MaglevEulerSwapRegistry is Ownable {
    event PoolRegistered(address indexed asset0, address indexed asset1, uint256 indexed fee, address pool);

    mapping(address => mapping(address => mapping(uint256 => address))) public getPool;

    constructor() Ownable(msg.sender) {}

    function registerPool(address _pool) external onlyOwner {
        address asset0 = IMaglevEulerSwap(_pool).asset0();
        address asset1 = IMaglevEulerSwap(_pool).asset1();
        uint256 fee = IMaglevEulerSwap(_pool).fee();

        getPool[asset0][asset1][fee] = _pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[asset0][asset1][fee] = _pool;

        emit PoolRegistered(asset0, asset1, fee, _pool);
    }
}
