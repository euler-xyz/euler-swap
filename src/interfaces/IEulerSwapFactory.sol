// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IEulerSwap} from "./IEulerSwap.sol";

interface IEulerSwapFactory {
    /// @notice Deploy a new EulerSwap pool with the given parameters
    /// @dev The pool address is deterministically generated using CREATE2 with a salt derived from
    ///      the euler account address and provided salt parameter. This allows the pool address to be
    ///      predicted before deployment.
    /// @param params Core pool parameters including vaults, account, fees, and curve shape
    /// @param initialState Initial state of the pool
    /// @param salt Unique value to generate deterministic pool address
    /// @return Address of the newly deployed pool
    function deployPool(IEulerSwap.Params memory params, IEulerSwap.InitialState memory initialState, bytes32 salt)
        external
        returns (address);

    /// @notice Uninstalls the pool associated with the Euler account
    /// @dev This function removes the pool from the factory's tracking and emits a PoolUninstalled event
    /// @dev The function can only be called by the Euler account that owns the pool
    /// @dev If no pool is installed for the caller, the function returns without any action
    function uninstallPool() external;

    /// @notice Compute the address of a new EulerSwap pool with the given parameters
    /// @dev The pool address is deterministically generated using CREATE2 with a salt derived from
    ///      the euler account address and provided salt parameter. This allows the pool address to be
    ///      predicted before deployment.
    /// @param poolParams Core pool parameters including vaults, account, and fee settings
    /// @param salt Unique value to generate deterministic pool address
    /// @return Address of the newly deployed pool
    function computePoolAddress(IEulerSwap.Params memory poolParams, bytes32 salt) external view returns (address);

    /// @notice Returns a slice of all deployed pools
    /// @dev Returns a subset of the pools array from start to end index
    /// @param start The starting index of the slice (inclusive)
    /// @param end The ending index of the slice (exclusive)
    /// @return An array containing the requested slice of pool addresses
    function poolsSlice(uint256 start, uint256 end) external view returns (address[] memory);

    /// @notice Returns all deployed pools
    /// @dev Returns the complete array of all pool addresses
    /// @return An array containing all pool addresses
    function pools() external view returns (address[] memory);

    /// @notice Returns the number of pools for a specific asset pair
    /// @dev Returns the length of the pool array for the given asset pair
    /// @param asset0 The address of the first asset
    /// @param asset1 The address of the second asset
    /// @return The number of pools for the specified asset pair
    function poolsByPairLength(address asset0, address asset1) external view returns (uint256);

    /// @notice Returns a slice of pools for a specific asset pair
    /// @dev Returns a subset of the pools array for the given asset pair from start to end index
    /// @param asset0 The address of the first asset
    /// @param asset1 The address of the second asset
    /// @param start The starting index of the slice (inclusive)
    /// @param end The ending index of the slice (exclusive)
    /// @return An array containing the requested slice of pool addresses for the asset pair
    function poolsByPairSlice(address asset0, address asset1, uint256 start, uint256 end)
        external
        view
        returns (address[] memory);

    /// @notice Returns all pools for a specific asset pair
    /// @dev Returns the complete array of pool addresses for the given asset pair
    /// @param asset0 The address of the first asset
    /// @param asset1 The address of the second asset
    /// @return An array containing all pool addresses for the specified asset pair
    function poolsByPair(address asset0, address asset1) external view returns (address[] memory);

    /// @notice Returns the pool address associated with a specific holder
    /// @dev Returns the pool address from the EulerAccountState mapping for the given holder
    /// @param who The address of the holder to query
    /// @return The address of the pool associated with the holder
    function poolByEulerAccount(address who) external view returns (address);

    /// @notice Returns the total number of deployed pools
    /// @dev Returns the length of the allPools array
    /// @return The total number of pools deployed through the factory
    function poolsLength() external view returns (uint256);
}
