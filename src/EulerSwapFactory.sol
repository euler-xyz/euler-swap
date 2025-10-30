// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IEulerSwapFactory, IEulerSwap} from "./interfaces/IEulerSwapFactory.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

import {EulerSwap} from "./EulerSwap.sol";
import {MetaProxyDeployer} from "./utils/MetaProxyDeployer.sol";

/// @title EulerSwapFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapFactory is IEulerSwapFactory, EVCUtil {
    /// @dev The EulerSwap code instance that will be proxied to
    address public immutable eulerSwapImpl;

    /// @dev Set of pool addresses deployed by this factory
    mapping(address pool => bool) public deployedPools;

    error Unauthorized();
    error OperatorNotInstalled();

    event PoolDeployed(
        address indexed asset0,
        address indexed asset1,
        address indexed eulerAccount,
        address pool,
        IEulerSwap.StaticParams sParams
    );

    constructor(address evc, address eulerSwapImpl_) EVCUtil(evc) {
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

        EulerSwap pool = EulerSwap(MetaProxyDeployer.deployMetaProxy(eulerSwapImpl, abi.encode(sParams), salt));
        deployedPools[address(pool)] = true;

        require(evc.isAccountOperatorAuthorized(sParams.eulerAccount, address(pool)), OperatorNotInstalled());

        (address asset0, address asset1) = pool.getAssets();
        emit PoolDeployed(asset0, asset1, sParams.eulerAccount, address(pool), sParams);

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
}
