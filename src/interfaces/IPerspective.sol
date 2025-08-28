// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

/// @title IPerspective
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A contract that verifies the properties of a vault.
interface IPerspective {
    /// @notice Checks if a vault is verified.
    /// @param vault The address of the vault to check.
    /// @return True if the vault is verified, false otherwise.
    function isVerified(address vault) external view returns (bool);
}
