// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

// TODO: to be replaced with solmate
import {Owned} from "./Owned.sol";

abstract contract ProtocolFee is Owned {
    uint256 public protocolFee;
    address public protocolFeeRecipient;

    constructor(address _feeOwner) Owned(_feeOwner) {}

    function setProtocolFee(uint256 newFee) external onlyOwner {
        protocolFee = newFee;
    }

    function setProtocolFeeRecipient(address newRecipient) external onlyOwner {
        protocolFeeRecipient = newRecipient;
    }
}
