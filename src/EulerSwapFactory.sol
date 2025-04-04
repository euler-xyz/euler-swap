// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IEulerSwapFactory, IEulerSwap} from "./interfaces/IEulerSwapFactory.sol";
import {EulerSwapHook} from "./EulerSwapHook.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {ProtocolFee} from "./base/ProtocolFee.sol";

/// @title EulerSwapFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapFactory is IEulerSwapFactory, EVCUtil, ProtocolFee {
    /// @dev An array to store all pools addresses.
    address[] private allPools;
    /// @dev Vaults must be deployed by this factory
    address public immutable evkFactory;
    /// @dev Mapping between euler account and EulerAccountState
    mapping(address eulerAccount => EulerAccountState state) private eulerAccountState;
    mapping(address asset0 => mapping(address asset1 => address[])) private poolMap;

    IPoolManager immutable poolManager;

    event PoolDeployed(
        address indexed asset0,
        address indexed asset1,
        address vault0,
        address vault1,
        uint256 indexed fee,
        address eulerAccount,
        uint256 reserve0,
        uint256 reserve1,
        uint256 priceX,
        uint256 priceY,
        uint256 concentrationX,
        uint256 concentrationY,
        address pool
    );
    event PoolUninstalled(address indexed asset0, address indexed asset1, address indexed eulerAccount, address pool);

    error InvalidQuery();
    error Unauthorized();
    error OldOperatorStillInstalled();
    error OperatorNotInstalled();
    error InvalidVaultImplementation();
    error SliceOutOfBounds();

    constructor(IPoolManager _manager, address evc, address evkFactory_, address feeOwner_) EVCUtil(evc) ProtocolFee(feeOwner_) {
        poolManager = _manager;
        evkFactory = evkFactory_;
    }

    /// @inheritdoc IEulerSwapFactory
    function deployPool(IEulerSwap.Params memory params, IEulerSwap.CurveParams memory curveParams, bytes32 salt)
        external
        returns (address)
    {
        require(_msgSender() == params.eulerAccount, Unauthorized());
        require(
            GenericFactory(evkFactory).isProxy(params.vault0) && GenericFactory(evkFactory).isProxy(params.vault1),
            InvalidVaultImplementation()
        );

        params.protocolFeeRecipient = protocolFeeRecipient;
        params.protocolFee = protocolFee;
        uninstall(params.eulerAccount);

        EulerSwapHook pool =
            new EulerSwapHook{salt: keccak256(abi.encode(params.eulerAccount, salt))}(poolManager, params, curveParams);

        updateEulerAccountState(params.eulerAccount, address(pool));

        pool.activate();

        emit PoolDeployed(
            pool.asset0(),
            pool.asset1(),
            params.vault0,
            params.vault1,
            pool.fee(),
            params.eulerAccount,
            params.currReserve0,
            params.currReserve1,
            curveParams.priceX,
            curveParams.priceY,
            curveParams.concentrationX,
            curveParams.concentrationY,
            address(pool)
        );

        return address(pool);
    }

    /// @inheritdoc IEulerSwapFactory
    function uninstallPool() external {
        uninstall(_msgSender());
    }

    /// @inheritdoc IEulerSwapFactory
    function computePoolAddress(
        IEulerSwap.Params memory poolParams,
        IEulerSwap.CurveParams memory curveParams,
        bytes32 salt
    ) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            keccak256(abi.encode(address(poolParams.eulerAccount), salt)),
                            keccak256(
                                abi.encodePacked(
                                    type(EulerSwapHook).creationCode, abi.encode(poolManager, poolParams, curveParams)
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    /// @inheritdoc IEulerSwapFactory
    function EVC() external view override(EVCUtil, IEulerSwapFactory) returns (address) {
        return address(evc);
    }

    /// @inheritdoc IEulerSwapFactory
    function poolByEulerAccount(address eulerAccount) external view returns (address) {
        return eulerAccountState[eulerAccount].pool;
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsSlice(uint256 start, uint256 end) external view returns (address[] memory) {
        return _getSlice(allPools, start, end);
    }

    /// @inheritdoc IEulerSwapFactory
    function pools() external view returns (address[] memory) {
        return _getSlice(allPools, 0, type(uint256).max);
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPairLength(address asset0, address asset1) external view returns (uint256) {
        return poolMap[asset0][asset1].length;
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPairSlice(address asset0, address asset1, uint256 start, uint256 end)
        external
        view
        returns (address[] memory)
    {
        return _getSlice(poolMap[asset0][asset1], start, end);
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPair(address asset0, address asset1) external view returns (address[] memory) {
        return _getSlice(poolMap[asset0][asset1], 0, type(uint256).max);
    }

    /// @notice Validates operator authorization for euler account and update the relevant EulerAccountState.
    /// @param eulerAccount The address of the euler account.
    /// @param newOperator The address of the new pool.
    function updateEulerAccountState(address eulerAccount, address newOperator) internal {
        require(evc.isAccountOperatorAuthorized(eulerAccount, newOperator), OperatorNotInstalled());

        (address asset0, address asset1) = _getAssets(newOperator);

        address[] storage poolMapArray = poolMap[asset0][asset1];

        eulerAccountState[eulerAccount] = EulerAccountState({
            pool: newOperator,
            allPoolsIndex: uint48(allPools.length),
            poolMapIndex: uint48(poolMapArray.length)
        });

        allPools.push(newOperator);
        poolMapArray.push(newOperator);
    }

    /// @notice Uninstalls the pool associated with the given Euler account
    /// @dev This function removes the pool from the factory's tracking and emits a PoolUninstalled event
    /// @dev The function checks if the operator is still installed and reverts if it is
    /// @dev If no pool exists for the account, the function returns without any action
    /// @param eulerAccount The address of the Euler account whose pool should be uninstalled
    function uninstall(address eulerAccount) internal {
        address pool = eulerAccountState[eulerAccount].pool;

        if (pool == address(0)) return;

        require(!evc.isAccountOperatorAuthorized(eulerAccount, pool), OldOperatorStillInstalled());

        (address asset0, address asset1) = _getAssets(pool);

        address[] storage poolMapArr = poolMap[asset0][asset1];

        swapAndPop(allPools, eulerAccountState[eulerAccount].allPoolsIndex);
        swapAndPop(poolMapArr, eulerAccountState[eulerAccount].poolMapIndex);

        delete eulerAccountState[eulerAccount];

        emit PoolUninstalled(asset0, asset1, eulerAccount, pool);
    }

    /// @notice Swaps the element at the given index with the last element and removes the last element
    /// @param arr The storage array to modify
    /// @param index The index of the element to remove
    function swapAndPop(address[] storage arr, uint256 index) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    /// @notice Retrieves the asset addresses for a given pool
    /// @dev Calls the pool contract to get its asset0 and asset1 addresses
    /// @param pool The address of the pool to query
    /// @return The addresses of asset0 and asset1 in the pool
    function _getAssets(address pool) internal view returns (address, address) {
        return (IEulerSwap(pool).asset0(), IEulerSwap(pool).asset1());
    }

    /// @notice Returns a slice of an array of addresses
    /// @dev Creates a new memory array containing elements from start to end index
    ///      If end is type(uint256).max, it will return all elements from start to the end of the array
    /// @param arr The storage array to slice
    /// @param start The starting index of the slice (inclusive)
    /// @param end The ending index of the slice (exclusive)
    /// @return A new memory array containing the requested slice of addresses
    function _getSlice(address[] storage arr, uint256 start, uint256 end) internal view returns (address[] memory) {
        uint256 length = arr.length;
        if (end == type(uint256).max) end = length;
        if (end < start || end > length) revert SliceOutOfBounds();

        address[] memory slice = new address[](end - start);
        for (uint256 i; i < end - start; ++i) {
            slice[i] = arr[start + i];
        }

        return slice;
    }
}
