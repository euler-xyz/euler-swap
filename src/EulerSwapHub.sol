// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {IEulerSwap, EulerSwap} from "./EulerSwap.sol";

contract EulerSwapHub is EVCUtil {
    struct HolderState {
        address pool;
        uint48 allPoolsIndex;
        uint48 poolMapIndex;
    }

    address public immutable evkFactory;
    mapping(address holder => HolderState) private holders;
    address[] private allPools;
    mapping(address asset0 => mapping(address asset1 => address[])) private poolMap;
    mapping(address owner => uint256 bitmask) public subaccountMap;

    error Unauthorized();
    error OperatorStillInstalled();
    error OperatorNotInstalled();
    error SliceOutOfBounds();
    error InvalidVaultImplementation();

    event PoolDeployed(address indexed asset0, address indexed asset1, address indexed holder, address pool);
    event PoolUninstalled(address indexed asset0, address indexed asset1, address indexed holder, address pool);

    constructor(address evc, address evkFactory_) EVCUtil(evc) {
        evkFactory = evkFactory_;
    }

    function deploy(EulerSwap.Params memory params, EulerSwap.CurveParams memory curveParams, bytes32 salt)
        external
        returns (address pool)
    {
        address me = _msgSender();
        require(me == params.eulerAccount, Unauthorized());
        require(
            GenericFactory(evkFactory).isProxy(params.vault0) && GenericFactory(evkFactory).isProxy(params.vault1),
            InvalidVaultImplementation()
        );

        uninstall();

        pool = address(new EulerSwap{salt: keccak256(abi.encode(me, salt))}(params, curveParams));
        require(evc.isAccountOperatorAuthorized(me, pool), OperatorNotInstalled());
        EulerSwap(pool).activate();

        (address asset0, address asset1) = _getAssets(pool);
        address[] storage poolMapArray = poolMap[asset0][asset1];

        holders[me] =
            HolderState({pool: pool, allPoolsIndex: uint48(allPools.length), poolMapIndex: uint48(poolMapArray.length)});

        allPools.push(pool);
        poolMapArray.push(pool);

        {
            address owner = _getOwner(me);
            subaccountMap[owner] |= 1 << (uint256(uint160(owner)) ^ uint256(uint160(me)));
        }

        emit PoolDeployed(asset0, asset1, me, pool);
    }

    function uninstall() public {
        address me = _msgSender();

        if (holders[me].pool == address(0)) return;
        require(!evc.isAccountOperatorAuthorized(me, holders[me].pool), OperatorStillInstalled());

        address pool = holders[me].pool;

        (address asset0, address asset1) = _getAssets(pool);

        _swapAndPop(allPools, holders[me].allPoolsIndex);
        _swapAndPop(poolMap[asset0][asset1], holders[me].poolMapIndex);

        delete holders[me];

        {
            address owner = _getOwner(me);
            subaccountMap[owner] &= ~(1 << (uint256(uint160(owner)) ^ uint256(uint160(me))));
        }

        emit PoolUninstalled(asset0, asset1, me, pool);
    }

    // View methods

    function poolByHolder(address who) external view returns (address) {
        return holders[who].pool;
    }

    function poolsLength() external view returns (uint256) {
        return allPools.length;
    }

    function poolsSlice(uint256 start, uint256 end) public view returns (address[] memory) {
        return _getSlice(allPools, start, end);
    }

    function pools() external view returns (address[] memory) {
        return poolsSlice(0, type(uint256).max);
    }

    function poolsByPairLength(address asset0, address asset1) external view returns (uint256) {
        return poolMap[asset0][asset1].length;
    }

    function poolsByPairSlice(address asset0, address asset1, uint256 start, uint256 end)
        public
        view
        returns (address[] memory)
    {
        return _getSlice(poolMap[asset0][asset1], start, end);
    }

    function poolsByPair(address asset0, address asset1) external view returns (address[] memory) {
        return poolsByPairSlice(asset0, asset1, 0, type(uint256).max);
    }

    // Internal utils

    function _swapAndPop(address[] storage arr, uint256 index) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

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

    function _getOwner(address who) internal view returns (address owner) {
        owner = evc.getAccountOwner(who);
        if (owner == address(0)) owner = who;
    }

    function _getAssets(address pool) internal view returns (address, address) {
        return (EulerSwap(pool).asset0(), EulerSwap(pool).asset1());
    }
}
