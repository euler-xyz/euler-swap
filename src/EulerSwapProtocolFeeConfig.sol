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
    error InvalidAdminAddress();
    error InvalidProtocolFee();
    error InvalidProtocolFeeRecipient();

    /// @notice Emitted when admin is set/changed
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    /// @notice Emitted when the default configuration is changed
    event DefaultUpdated(address indexed oldRecipient, address indexed newRecipient, uint64 oldFee, uint64 newFee);
    /// @notice Emitted when a per-pool override is created or changed
    event OverrideSet(address indexed pool, address indexed recipient, uint64 fee);
    /// @notice Emitted when a per-pool override is removed (and thus falls back to the default)
    event OverrideRemoved(address indexed pool);

    constructor(address evc, address admin_) EVCUtil(evc) {
        _validateAdminAddress(admin_);

        emit AdminUpdated(address(0), admin_);

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
        _validateAdminAddress(newAdmin);

        emit AdminUpdated(admin, newAdmin);

        admin = newAdmin;
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function setDefault(address recipient, uint64 fee) external onlyAdmin {
        require(fee <= MAX_PROTOCOL_FEE, InvalidProtocolFee());
        require(fee == 0 || recipient != address(0), InvalidProtocolFeeRecipient());

        emit DefaultUpdated(defaultRecipient, recipient, defaultFee, fee);

        defaultRecipient = recipient;
        defaultFee = fee;
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function setOverride(address pool, address recipient, uint64 fee) external onlyAdmin {
        require(fee <= MAX_PROTOCOL_FEE, InvalidProtocolFee());

        emit OverrideSet(pool, recipient, fee);

        overrides[pool] = Override({exists: true, recipient: recipient, fee: fee});
    }

    /// @inheritdoc IEulerSwapProtocolFeeConfig
    function removeOverride(address pool) external onlyAdmin {
        emit OverrideRemoved(pool);

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

    /// @dev Ensures the admin is not a known sub-account, since they are not allowed
    function _validateAdminAddress(address addr) internal view {
        address owner = evc.getAccountOwner(addr);
        require(owner == addr || owner == address(0), InvalidAdminAddress());
    }
}
