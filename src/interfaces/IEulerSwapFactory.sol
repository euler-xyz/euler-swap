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
    ) external payable returns (address);

    /// @notice Uninstalls the pool associated with the Euler account
    /// @dev This function removes the pool from the factory's tracking and emits a PoolUninstalled event
    /// @dev The function can only be called by the Euler account that owns the pool
    /// @dev If no pool is installed for the caller, the function returns without any action
    function uninstallPool() external;

    /// @notice Remove a pool from the pools and poolsByPair lists. This can be used to
    /// clean-up incorrectly configured pools. Only callable by the custodian.
    /// @param pool Address of the EulerSwap instance to remove.
    function custodianUninstallPool(address pool) external;

    /// @notice Changes the address with custodian privileges. Only callable by the custodian.
    /// @param newCustodian New address to give custodian privileges. Caller gives up the privileges.
    function transferCustodian(address newCustodian) external;

    /// @notice Updates the minimum validity bond required to create new pools. Validity bonds
    /// are in native token (ie ETH).
    /// @param newMinimum The new minimum bond value, in native token
    function setMinimumValidityBond(uint256 newMinimum) external;

    /// @notice Attempt to remove a pool from the pools and poolsByPair lists. Anyone can invoke
    /// this function in order to retrieve the pool's posted validity bond. This function will
    /// retrieve a quote and actually attempt to execute a swap for that quote. If it succeeds,
    /// the function will revert. If it fails with E_AccountLiquidity, then the bond is transferred
    /// to the caller.
    /// @param poolAddr Pool that the caller believe is issuing invalid quotes.
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amount The amount of token to quote
    /// @param exactIn Whether the amount parameter refers to an input or output amount
    /// @param recipient Address to send the validity bond, if challenge was successful
    function challengePool(
        address poolAddr,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool exactIn,
        address recipient
    ) external;

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

    /// @notice Size of validity bond for a given pool, in native token (ie ETH).
    /// @param pool EulerSwap instance address.
    /// @return The size of the validity bond, or 0 if none.
    function validityBond(address pool) external view returns (uint256);
}
