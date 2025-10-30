// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IEulerSwapProtocolFeeConfig} from "./interfaces/IEulerSwapProtocolFeeConfig.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";

/// @title EulerSwapProtocolFeeConfig contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapProtocolFeeConfig is IEulerSwapProtocolFeeConfig, EVCUtil {
    /// @dev Protocol fee admin
    address public admin;

    /// @dev Admin is not allowed to set a protocol fee larger than this
    uint64 public constant MAX_PROTOCOL_FEE = 0.15e18;

    /// @dev Destination of collected protocol fees, unless overridden
    address public defaultRecipient;
    /// @dev Default protocol fee, 1e18-scale
    uint64 public defaultFee;

    struct Override {
        bool exists;
        address recipient;
        uint64 fee;
    }

    /// @dev EulerSwap-instance specific fee override
    mapping(address pool => Override) public overrides;

    error Unauthorized();
    error InvalidProtocolFee();

    constructor(address evc, address admin_) EVCUtil(evc) {
        admin = admin_;
    }

    modifier onlyAdmin() {
        // Ensures that the caller is not an operator, controller, etc
        _authenticateCallerWithStandardContextState(true);

        require(_msgSender() == admin, Unauthorized());

        _;
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function setDefault(address recipient, uint64 fee) external onlyAdmin {
        require(fee <= MAX_PROTOCOL_FEE, InvalidProtocolFee());

        defaultRecipient = recipient;
        defaultFee = fee;
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function setOverride(address pool, address recipient, uint64 fee) external onlyAdmin {
        require(fee <= MAX_PROTOCOL_FEE, InvalidProtocolFee());

        overrides[pool] = Override({exists: true, recipient: recipient, fee: fee});
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function removeOverride(address pool) external onlyAdmin {
        delete overrides[pool];
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function getProtocolFee(address pool) external view returns (address recipient, uint64 fee) {
        Override memory o = overrides[pool];

        if (o.exists) {
            recipient = o.recipient;
            fee = o.fee;

            if (recipient == address(0)) recipient = defaultRecipient;
        } else {
            recipient = defaultRecipient;
            fee = defaultFee;
        }
    }
}
