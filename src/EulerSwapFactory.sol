// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEulerSwapFactory, IEulerSwap} from "./interfaces/IEulerSwapFactory.sol";
import {EulerSwap} from "./EulerSwap.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";

/// @title EulerSwapFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapFactory is IEulerSwapFactory, EVCUtil {
    /// @dev An array to store all pools addresses.
    address[] public allPools;
    /// @dev Mapping between euler account and deployed pool that is currently set as operator
    mapping(address eulerAccount => address operator) public eulerAccountToPool;
    /// @dev Vaults must be deployed by this factory
    address public immutable evkFactory;

    event PoolDeployed(
        address indexed asset0,
        address indexed asset1,
        address vault0,
        address vault1,
        uint256 indexed feeMultiplier,
        address eulerAccount,
        uint256 reserve0,
        uint256 reserve1,
        uint256 priceX,
        uint256 priceY,
        uint256 concentrationX,
        uint256 concentrationY,
        address pool
    );

    error InvalidQuery();
    error Unauthorized();
    error OldOperatorStillInstalled();
    error OperatorNotInstalled();
    error InvalidVaultImplementation();

    constructor(address evc, address evkFactory_) EVCUtil(evc) {
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

        EulerSwap pool = new EulerSwap{salt: keccak256(abi.encode(params.eulerAccount, salt))}(params, curveParams);

        checkEulerAccountOperators(params.eulerAccount, address(pool));

        allPools.push(address(pool));

        EulerSwap(pool).activate();

        emit PoolDeployed(
            pool.asset0(),
            pool.asset1(),
            params.vault0,
            params.vault1,
            pool.feeMultiplier(),
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
                                abi.encodePacked(type(EulerSwap).creationCode, abi.encode(poolParams, curveParams))
                            )
                        )
                    )
                )
            )
        );
    }

    function EVC() external view override(EVCUtil, IEulerSwapFactory) returns (address) {
        return address(evc);
    }

    /// @inheritdoc IEulerSwapFactory
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @inheritdoc IEulerSwapFactory
    function getAllPoolsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = allPools.length;
        if (_end == type(uint256).max) _end = length;
        if (_end < _start || _end > length) revert InvalidQuery();

        address[] memory allPoolsList = new address[](_end - _start);
        for (uint256 i; i < _end - _start; ++i) {
            allPoolsList[i] = allPools[_start + i];
        }

        return allPoolsList;
    }

    /// @notice Validates operator authorization for euler account. First checks if the account has an existing operator
    /// and ensures it is deauthorized. Then verifies the new pool is authorized as an operator. Finally, updates the
    /// mapping to track the new pool as the account's operator.
    /// @param eulerAccount The address of the euler account.
    /// @param newPool The address of the new pool.
    function checkEulerAccountOperators(address eulerAccount, address newPool) internal {
        address operator = eulerAccountToPool[eulerAccount];

        if (operator != address(0)) {
            require(!evc.isAccountOperatorAuthorized(eulerAccount, operator), OldOperatorStillInstalled());
        }

        require(evc.isAccountOperatorAuthorized(eulerAccount, newPool), OperatorNotInstalled());

        eulerAccountToPool[eulerAccount] = newPool;
    }
}
