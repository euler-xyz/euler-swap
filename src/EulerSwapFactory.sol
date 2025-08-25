// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

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
    using SafeERC20 for IERC20;

    /// @dev Vaults must be deployed by this factory
    address public immutable evkFactory;
    /// @dev The EulerSwap code instance that will be proxied to
    address public immutable eulerSwapImpl;
    /// @dev Custodian who can set the minimum validity bond, and remove pools from the factory lists
    address public custodian;
    /// @dev Minimum size of validity bond, in native token
    uint256 public minimumValidityBond;

    /// @dev Mapping from euler account to pool, if installed
    mapping(address eulerAccount => address) internal installedPools;
    /// @dev Mapping from pool to validity bond amount
    mapping(address pool => uint256) internal validityBonds;
    /// @dev Set of all pool addresses
    EnumerableSet.AddressSet internal allPools;
    /// @dev Mapping from sorted pair of underlyings to set of pools
    mapping(address asset0 => mapping(address asset1 => EnumerableSet.AddressSet)) internal poolMap;

    event PoolDeployed(
        address indexed asset0,
        address indexed asset1,
        address indexed eulerAccount,
        address pool,
        IEulerSwap.StaticParams sParams,
        uint256 validityBond
    );
    event PoolUninstalled(address indexed asset0, address indexed asset1, address indexed eulerAccount, address pool);
    event PoolChallenged(
        address indexed challenger,
        address indexed pool,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool exactIn,
        uint256 bondAmount,
        address recipient
    );

    error InvalidQuery();
    error Unauthorized();
    error OldOperatorStillInstalled();
    error OperatorNotInstalled();
    error InvalidVaultImplementation();
    error SliceOutOfBounds();
    error InvalidProtocolFee();
    error InsufficientValidityBond();
    error ChallengeNoBondAvailable();
    error ChallengeBadAssets();
    error ChallengeLiquidityDeferred();
    error ChallengeMissingBond();
    error ChallengeUnauthorized();
    error ChallengeSwapSucceeded();
    error ChallengeSwapNotLiquidityFailure();

    error E_AccountLiquidity(); // From EVK

    constructor(
        address evc,
        address evkFactory_,
        address eulerSwapImpl_,
        address feeOwner_,
        address feeRecipientSetter_,
        address custodian_
    ) EVCUtil(evc) ProtocolFee(feeOwner_, feeRecipientSetter_) {
        evkFactory = evkFactory_;
        eulerSwapImpl = eulerSwapImpl_;
        custodian = custodian_;
    }

    function isValidVault(address v) internal view returns (bool) {
        return GenericFactory(evkFactory).isProxy(v);
    }

    /// @inheritdoc IEulerSwapFactory
    function deployPool(
        IEulerSwap.StaticParams memory sParams,
        IEulerSwap.DynamicParams memory dParams,
        IEulerSwap.InitialState memory initialState,
        bytes32 salt
    ) external payable returns (address) {
        require(_msgSender() == sParams.eulerAccount, Unauthorized());
        require(isValidVault(sParams.supplyVault0) && isValidVault(sParams.supplyVault1), InvalidVaultImplementation());
        require(sParams.borrowVault0 == address(0) || isValidVault(sParams.borrowVault0), InvalidVaultImplementation());
        require(sParams.borrowVault1 == address(0) || isValidVault(sParams.borrowVault1), InvalidVaultImplementation());
        require(
            sParams.protocolFee == protocolFee && sParams.protocolFeeRecipient == protocolFeeRecipient,
            InvalidProtocolFee()
        );
        require(msg.value >= minimumValidityBond, InsufficientValidityBond());

        uninstall(sParams.eulerAccount, false);

        EulerSwap pool = EulerSwap(MetaProxyDeployer.deployMetaProxy(eulerSwapImpl, abi.encode(sParams), salt));
        require(evc.isAccountOperatorAuthorized(sParams.eulerAccount, address(pool)), OperatorNotInstalled());

        (address asset0, address asset1) = pool.getAssets();

        installedPools[sParams.eulerAccount] = address(pool);
        validityBonds[address(pool)] = msg.value;

        allPools.add(address(pool));
        poolMap[asset0][asset1].add(address(pool));

        emit PoolDeployed(asset0, asset1, sParams.eulerAccount, address(pool), sParams, msg.value);

        pool.activate(dParams, initialState);

        return address(pool);
    }

    /// @inheritdoc IEulerSwapFactory
    function uninstallPool() external {
        uninstall(_msgSender(), false);
    }

    modifier onlyCustodian() {
        require(_msgSender() == custodian, Unauthorized());
        _;
    }

    /// @inheritdoc IEulerSwapFactory
    function custodianUninstallPool(address pool) external onlyCustodian {
        address eulerAccount = IEulerSwap(pool).getStaticParams().eulerAccount;
        uninstall(eulerAccount, true);
    }

    /// @inheritdoc IEulerSwapFactory
    function transferCustodian(address newCustodian) external onlyCustodian {
        custodian = newCustodian;
    }

    /// @inheritdoc IEulerSwapFactory
    function setMinimumValidityBond(uint256 newMinimum) external onlyCustodian {
        minimumValidityBond = newMinimum;
    }

    /// @inheritdoc IEulerSwapFactory
    function challengePool(
        address poolAddr,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool exactIn,
        address recipient
    ) external {
        IEulerSwap pool = IEulerSwap(poolAddr);
        address eulerAccount = pool.getStaticParams().eulerAccount;
        bool asset0IsInput;

        require(validityBonds[poolAddr] > 0, ChallengeNoBondAvailable());

        {
            (address asset0, address asset1) = pool.getAssets();
            require(
                (asset0 == tokenIn && asset1 == tokenOut) || (asset0 == tokenOut && asset1 == tokenIn),
                ChallengeBadAssets()
            );
            asset0IsInput = asset0 == tokenIn;
        }

        require(!evc.isAccountStatusCheckDeferred(eulerAccount), ChallengeLiquidityDeferred());

        uint256 quote = pool.computeQuote(tokenIn, tokenOut, amount, exactIn);

        {
            (bool success, bytes memory error) = address(this).call(
                abi.encodeWithSelector(
                    this.challengePoolAttempt.selector,
                    msg.sender,
                    poolAddr,
                    asset0IsInput,
                    tokenIn,
                    exactIn ? amount : quote,
                    exactIn ? quote : amount
                )
            );
            require(!success, ChallengeSwapSucceeded());
            require(bytes4(error) == E_AccountLiquidity.selector, ChallengeSwapNotLiquidityFailure());
        }

        uint256 bondAmount = redeemValidityBond(poolAddr, recipient);

        emit PoolChallenged(msg.sender, poolAddr, tokenIn, tokenOut, amount, exactIn, bondAmount, recipient);

        uninstall(eulerAccount, true);
    }

    function challengePoolAttempt(
        address challenger,
        address poolAddr,
        bool asset0IsInput,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        require(msg.sender == address(this), ChallengeUnauthorized());

        IERC20(tokenIn).safeTransferFrom(challenger, poolAddr, amountIn);

        if (asset0IsInput) IEulerSwap(poolAddr).swap(0, amountOut, challenger, "");
        else IEulerSwap(poolAddr).swap(amountOut, 0, challenger, "");
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

    /// @inheritdoc IEulerSwapFactory
    function poolByEulerAccount(address eulerAccount) external view returns (address) {
        return installedPools[eulerAccount];
    }

    /// @inheritdoc IEulerSwapFactory
    function validityBond(address pool) external view returns (uint256) {
        return validityBonds[pool];
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

    /// @notice Uninstalls the pool associated with the given Euler account
    /// @dev This function removes the pool from the factory's tracking and emits a PoolUninstalled event
    /// @dev The function checks if the operator is still installed and reverts if it is
    /// @dev If no pool exists for the account, the function returns without any action
    /// @param eulerAccount The address of the Euler account whose pool should be uninstalled
    /// @param forced Whether this is a forced uninstall, vs a user-requested uninstall
    function uninstall(address eulerAccount, bool forced) internal {
        address pool = installedPools[eulerAccount];
        if (pool == address(0)) return;

        if (!forced) {
            require(!evc.isAccountOperatorAuthorized(eulerAccount, pool), OldOperatorStillInstalled());
            delete installedPools[eulerAccount];
        }

        (address asset0, address asset1) = IEulerSwap(pool).getAssets();

        allPools.remove(pool);
        poolMap[asset0][asset1].remove(pool);

        redeemValidityBond(pool, eulerAccount);

        emit PoolUninstalled(asset0, asset1, eulerAccount, pool);
    }

    function redeemValidityBond(address pool, address recipient) internal returns (uint256 bondAmount) {
        bondAmount = validityBonds[pool];

        if (bondAmount != 0) {
            (bool success,) = recipient.call{value: bondAmount}("");
            require(success, ChallengeMissingBond());
            validityBonds[pool] = 0;
        }
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

    function _eulerSwapImpl() internal view override returns (address) {
        return eulerSwapImpl;
    }
}
