// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IEulerSwapFactory, IEulerSwap} from "./interfaces/IEulerSwapFactory.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

import {EulerSwap} from "./EulerSwap.sol";
import {ProtocolFee} from "./utils/ProtocolFee.sol";
import {MetaProxyDeployer} from "./utils/MetaProxyDeployer.sol";

/// @title EulerSwapFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapFactory is IEulerSwapFactory, EVCUtil, ProtocolFee {
    /// @dev The EulerSwap code instance that will be proxied to
    address public immutable eulerSwapImpl;

    /// @dev Set of pool addresses deployed by this factory
    mapping(address pool => bool) public deployedPools;

    error Unauthorized();
    error OperatorNotInstalled();
    error InvalidProtocolFee();

    constructor(address evc, address eulerSwapImpl_, address feeOwner_, address feeRecipientSetter_)
        EVCUtil(evc)
        ProtocolFee(feeOwner_, feeRecipientSetter_)
    {
        eulerSwapImpl = eulerSwapImpl_;
    }

    /// @inheritdoc IEulerSwapFactory
    function deployPool(
        IEulerSwap.StaticParams memory sParams,
        IEulerSwap.DynamicParams memory dParams,
        IEulerSwap.InitialState memory initialState,
        bytes32 salt
    ) external returns (address) {
        require(_msgSender() == sParams.eulerAccount, Unauthorized());
        require(
            sParams.protocolFee == protocolFee && sParams.protocolFeeRecipient == protocolFeeRecipient,
            InvalidProtocolFee()
        );

        EulerSwap pool = EulerSwap(MetaProxyDeployer.deployMetaProxy(eulerSwapImpl, abi.encode(sParams), salt));
        deployedPools[address(pool)] = true;

        require(evc.isAccountOperatorAuthorized(sParams.eulerAccount, address(pool)), OperatorNotInstalled());

        pool.activate(dParams, initialState);

        return address(pool);
    }

    /// @inheritdoc IEulerSwapFactory
    function creationCode(IEulerSwap.StaticParams memory sParams) public view returns (bytes memory) {
        return MetaProxyDeployer.creationCodeMetaProxy(eulerSwapImpl, abi.encode(sParams));
    }

    /// @inheritdoc IEulerSwapFactory
    function computePoolAddress(IEulerSwap.StaticParams memory sParams, bytes32 salt) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode(sParams))))
                )
            )
        );
    }

    /// @dev For ProtocolFee access
    function _eulerSwapImpl() internal view override returns (address) {
        return eulerSwapImpl;
    }
}
