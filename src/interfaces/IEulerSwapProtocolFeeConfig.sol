// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IEulerSwapProtocolFeeConfig {
    /// @notice Change the admin
    /// @param newAdmin New admin address (can be address(0) to renounce)
    function setAdmin(address newAdmin) external;

    /// @notice Update the default protocol fee settings
    /// @param recipient Address to receive the protocol fees
    /// @param fee Proportion of LP fees claimed as protocol fees (1e18 scale). Must be <= 15%.
    function setDefault(address recipient, uint64 fee) external;

    /// @notice Override a particular pool's protocol fee settings
    /// @param pool The EulerSwap instance to override
    /// @param recipient Address to receive the protocol fees. If address(0), then use the default recipient.
    /// @param fee Proportion of LP fees claimed as protocol fees (1e18 scale). Must be <= 15%.
    function setOverride(address pool, address recipient, uint64 fee) external;

    /// @notice Removes an override for a particular pool
    /// @param pool The EulerSwap instance
    function removeOverride(address pool) external;

    /// @notice Retrieve protocol fee configuration for a given pool
    /// @param pool Which pool to read the config for
    /// @return recipient Address to receive the protocol fees
    /// @return fee Proportion of LP fees claimed as protocol fees (1e18 scale)
    function getProtocolFee(address pool) external view returns (address recipient, uint64 fee);
}
