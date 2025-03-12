// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IEulerSwap} from "./IEulerSwap.sol";

interface IEulerSwapFactory {
    /// @notice Deploy a new EulerSwap pool with the given parameters
    /// @dev The pool address is deterministically generated using CREATE2 with a salt derived from
    ///      the euler account address and provided salt parameter. This allows the pool address to be
    ///      predicted before deployment.
    /// @param params Core pool parameters including vaults, account, and fee settings
    /// @param curveParams Parameters defining the curve shape including prices and concentrations
    /// @param salt Unique value to generate deterministic pool address
    /// @return Address of the newly deployed pool
    function deployPool(IEulerSwap.Params memory params, IEulerSwap.CurveParams memory curveParams, bytes32 salt)
        external
        returns (address);

    /// @notice Compute the address of a new EulerSwap pool with the given parameters
    /// @dev The pool address is deterministically generated using CREATE2 with a salt derived from
    ///      the euler account address and provided salt parameter. This allows the pool address to be
    ///      predicted before deployment.
    /// @param poolParams Core pool parameters including vaults, account, and fee settings
    /// @param curveParams Parameters defining the curve shape including prices and concentrations
    /// @param salt Unique value to generate deterministic pool address
    /// @return Address of the newly deployed pool
    function computePoolAddress(
        IEulerSwap.Params memory poolParams,
        IEulerSwap.CurveParams memory curveParams,
        bytes32 salt
    ) external view returns (address);
    function EVC() external view returns (address);
    /// @notice Get the length of `allPools` array.
    /// @return `allPools` length.
    function allPoolsLength() external view returns (uint256);
    /// @notice Get the address of the pool at the given index in the `allPools` array.
    /// @param index The index of the pool to retrieve.
    /// @return The address of the pool at the given index.
    function allPools(uint256 index) external view returns (address);
    /// @notice Get a slice of the deployed pools array.
    /// @param start Start index of the slice.
    /// @param end End index of the slice.
    /// @return An array containing the slice of the deployed pools.
    function getAllPoolsListSlice(uint256 start, uint256 end) external view returns (address[] memory);
}
