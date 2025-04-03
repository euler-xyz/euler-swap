// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

// TODO: to be replaced with solmate
import {Owned} from "./Owned.sol";

abstract contract ProtocolFee is Owned {
    uint256 public protocolFee;
    address public protocolFeeRecipient;

    error InvalidFee();

    constructor(address _feeOwner) Owned(_feeOwner) {}

    /// @notice Set the protocol fee, expressed as a percentage of LP fee
    /// @param newFee The new protocol fee, in WAD units (0.10e18 = 10%)
    function setProtocolFee(uint256 newFee) external onlyOwner {
        if (newFee > (1e18 - 1)) revert InvalidFee();
        protocolFee = newFee;
    }

    function setProtocolFeeRecipient(address newRecipient) external onlyOwner {
        protocolFeeRecipient = newRecipient;
    }
}
