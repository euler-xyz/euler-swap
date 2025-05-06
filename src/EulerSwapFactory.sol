// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

import {IEulerSwapFactory, IEulerSwap} from "./interfaces/IEulerSwapFactory.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";

import {EulerSwap} from "./EulerSwap.sol";
import {ProtocolFee} from "./utils/ProtocolFee.sol";
import {MetaProxyDeployer} from "./utils/MetaProxyDeployer.sol";

/// @title EulerSwapFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapFactory is IEulerSwapFactory, EVCUtil, ProtocolFee {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Vaults must be deployed by this factory
    address public immutable evkFactory;
    /// @dev The EulerSwap code instance that will be proxied to
    address public immutable eulerSwapImpl;

    /// @dev Mapping from euler account to pool, if installed
    mapping(address eulerAccount => address) internal installedPools;
    /// @dev Set of all pool addresses
    EnumerableSet.AddressSet internal allPools;
    /// @dev Mapping from sorted pair of underlyings to set of pools
    mapping(address asset0 => mapping(address asset1 => EnumerableSet.AddressSet)) internal poolMap;

    event PoolDeployed(address indexed asset0, address indexed asset1, address indexed eulerAccount, address pool);
    event PoolConfig(address indexed pool, IEulerSwap.Params params, IEulerSwap.InitialState initialState);
    event PoolUninstalled(address indexed asset0, address indexed asset1, address indexed eulerAccount, address pool);

    error InvalidQuery();
    error Unauthorized();
    error OldOperatorStillInstalled();
    error OperatorNotInstalled();
    error InvalidVaultImplementation();
    error SliceOutOfBounds();
    error InvalidProtocolFee();

    constructor(address evc, address evkFactory_, address eulerSwapImpl_, address feeOwner_)
        EVCUtil(evc)
        ProtocolFee(feeOwner_)
    {
        evkFactory = evkFactory_;
        eulerSwapImpl = eulerSwapImpl_;
    }

    /// @inheritdoc IEulerSwapFactory
    function deployPool(IEulerSwap.Params memory params, IEulerSwap.InitialState memory initialState, bytes32 salt)
        external
        returns (address)
    {
        require(_msgSender() == params.eulerAccount, Unauthorized());
        require(
            GenericFactory(evkFactory).isProxy(params.vault0) && GenericFactory(evkFactory).isProxy(params.vault1),
            InvalidVaultImplementation()
        );
        require(
            params.protocolFee == protocolFee && params.protocolFeeRecipient == protocolFeeRecipient,
            InvalidProtocolFee()
        );

        uninstall(params.eulerAccount);

        EulerSwap pool = EulerSwap(MetaProxyDeployer.deployMetaProxy(eulerSwapImpl, abi.encode(params), salt));

        updateEulerAccountState(params.eulerAccount, address(pool));

        pool.activate(initialState);

        (address asset0, address asset1) = pool.getAssets();
        emit PoolDeployed(asset0, asset1, params.eulerAccount, address(pool));
        emit PoolConfig(address(pool), params, initialState);

        return address(pool);
    }

    /// @inheritdoc IEulerSwapFactory
    function uninstallPool() external {
        uninstall(_msgSender());
    }

    /// @inheritdoc IEulerSwapFactory
    function computePoolAddress(IEulerSwap.Params memory poolParams, bytes32 salt) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(MetaProxyDeployer.creationCodeMetaProxy(eulerSwapImpl, abi.encode(poolParams)))
                        )
                    )
                )
            )
        );
    }

    /// @inheritdoc IEulerSwapFactory
    function poolByEulerAccount(address eulerAccount) external view returns (address) {
        return installedPools[eulerAccount];
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsLength() external view returns (uint256) {
        return allPools.length();
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsSlice(uint256 start, uint256 end) external view returns (address[] memory) {
        return getSlice(allPools, start, end);
    }

    /// @inheritdoc IEulerSwapFactory
    function pools() external view returns (address[] memory) {
        return allPools.values();
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPairLength(address asset0, address asset1) external view returns (uint256) {
        return poolMap[asset0][asset1].length();
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPairSlice(address asset0, address asset1, uint256 start, uint256 end)
        external
        view
        returns (address[] memory)
    {
        return getSlice(poolMap[asset0][asset1], start, end);
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPair(address asset0, address asset1) external view returns (address[] memory) {
        return poolMap[asset0][asset1].values();
    }

    /// @notice Validates operator authorization for euler account and update the relevant EulerAccountState.
    /// @param eulerAccount The address of the euler account.
    /// @param newOperator The address of the new pool.
    function updateEulerAccountState(address eulerAccount, address newOperator) internal {
        require(evc.isAccountOperatorAuthorized(eulerAccount, newOperator), OperatorNotInstalled());

        (address asset0, address asset1) = IEulerSwap(newOperator).getAssets();

        installedPools[eulerAccount] = newOperator;

        allPools.add(newOperator);
        poolMap[asset0][asset1].add(newOperator);
    }

    /// @notice Uninstalls the pool associated with the given Euler account
    /// @dev This function removes the pool from the factory's tracking and emits a PoolUninstalled event
    /// @dev The function checks if the operator is still installed and reverts if it is
    /// @dev If no pool exists for the account, the function returns without any action
    /// @param eulerAccount The address of the Euler account whose pool should be uninstalled
    function uninstall(address eulerAccount) internal {
        address pool = installedPools[eulerAccount];

        if (pool == address(0)) return;

        require(!evc.isAccountOperatorAuthorized(eulerAccount, pool), OldOperatorStillInstalled());

        (address asset0, address asset1) = IEulerSwap(pool).getAssets();

        allPools.remove(pool);
        poolMap[asset0][asset1].remove(pool);

        delete installedPools[eulerAccount];

        emit PoolUninstalled(asset0, asset1, eulerAccount, pool);
    }

    /// @notice Returns a slice of an array of addresses
    /// @dev Creates a new memory array containing elements from start to end index
    ///      If end is type(uint256).max, it will return all elements from start to the end of the array
    /// @param arr The storage array to slice
    /// @param start The starting index of the slice (inclusive)
    /// @param end The ending index of the slice (exclusive)
    /// @return A new memory array containing the requested slice of addresses
    function getSlice(EnumerableSet.AddressSet storage arr, uint256 start, uint256 end)
        internal
        view
        returns (address[] memory)
    {
        uint256 length = arr.length();
        if (end == type(uint256).max) end = length;
        if (end < start || end > length) revert SliceOutOfBounds();

        address[] memory slice = new address[](end - start);
        for (uint256 i; i < end - start; ++i) {
            slice[i] = arr.at(start + i);
        }

        return slice;
    }
}
