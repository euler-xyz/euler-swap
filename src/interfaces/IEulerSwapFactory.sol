// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IEulerSwap} from "./IEulerSwap.sol";

interface IEulerSwapFactory {
    /// @notice Deploy a new EulerSwap pool with the given parameters
    /// @dev The pool address is deterministically generated using CREATE2 with a salt derived from
    ///      the euler account address and provided salt parameter. This allows the pool address to be
    ///      predicted before deployment.
    /// @param sParams Static parameters
    /// @param dParams Dynamic parameters
    /// @param initialState Initial state of the pool
    /// @param salt Unique value to generate deterministic pool address
    /// @return Address of the newly deployed pool
    function deployPool(
        IEulerSwap.StaticParams memory sParams,
        IEulerSwap.DynamicParams memory dParams,
        IEulerSwap.InitialState memory initialState,
        bytes32 salt
    ) external returns (address);

    /// @notice Set of pools deployed by this factory.
    /// @param pool Address to check
    function deployedPools(address pool) external view returns (bool);

    /// @notice Given a potential pool's static parameters, this function returns the creation
    /// code that will be used to compute the pool's address.
    function creationCode(IEulerSwap.StaticParams memory sParams) external view returns (bytes memory);

    /// @notice Compute the address of a new EulerSwap pool with the given parameters
    /// @dev The pool address is deterministically generated using CREATE2 with a salt derived from
    ///      the euler account address and provided salt parameter. This allows the pool address to be
    ///      predicted before deployment.
    /// @param sParams Static parameters
    /// @param salt Unique value to generate deterministic pool address
    /// @return Address of the newly deployed pool
    function computePoolAddress(IEulerSwap.StaticParams memory sParams, bytes32 salt) external view returns (address);
}
