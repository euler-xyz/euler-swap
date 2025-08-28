// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Owned} from "solmate/auth/Owned.sol";
import {UniswapHook} from "../UniswapHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

abstract contract ProtocolFee is Owned {
    uint256 public protocolFee;
    address public protocolFeeRecipient;
    address public immutable recipientSetter;
    uint256 public immutable deploymentTimestamp;

    uint256 public constant MIN_PROTOCOL_FEE = 0.1e18; // 10%
    uint256 public constant MAX_PROTOCOL_FEE = 0.25e18; // 25%

    error InvalidFee();
    error RecipientSetAlready();

    event ProtocolFeeSet(uint256 protocolFee);
    event ProtocolFeeRecipientSet(address protocolFeeRecipient);

    constructor(address _feeOwner, address _recipientSetter) Owned(_feeOwner) {
        deploymentTimestamp = block.timestamp;
        recipientSetter = _recipientSetter;
    }

    function _eulerSwapImpl() internal view virtual returns (address) {}

    function _poolManager() internal view returns (IPoolManager) {
        return UniswapHook(_eulerSwapImpl()).poolManager();
    }

    /// @notice Permissionlessly enable a minimum protocol fee after 1 year
    /// @dev All of the following conditions must be met:
    /// EulerSwap is deployed on a chain with Uniswap v4
    /// The protocol fee can only be enabled after 1 year of deployment
    /// The fee recipient MUST be specified
    /// The protocol fee was not previously set
    function enableProtocolFee() external {
        require(
            address(_poolManager()) != address(0) && block.timestamp >= (deploymentTimestamp + 365 days)
                && protocolFeeRecipient != address(0) && protocolFee == 0,
            InvalidFee()
        );
        protocolFee = MIN_PROTOCOL_FEE;
        emit ProtocolFeeSet(protocolFee);
    }

    /// @notice Set the protocol fee, expressed as a percentage of LP fee
    /// @param newFee The new protocol fee, in WAD units (0.10e18 = 10%)
    function setProtocolFee(uint256 newFee) external onlyOwner {
        require(
            MIN_PROTOCOL_FEE <= newFee && newFee <= MAX_PROTOCOL_FEE && protocolFeeRecipient != address(0), InvalidFee()
        );
        protocolFee = newFee;
        emit ProtocolFeeSet(protocolFee);
    }

    function setProtocolFeeRecipient(address newRecipient) external {
        require(msg.sender == recipientSetter && protocolFeeRecipient == address(0), RecipientSetAlready());
        protocolFeeRecipient = newRecipient;
        emit ProtocolFeeRecipientSet(protocolFeeRecipient);
    }
}
