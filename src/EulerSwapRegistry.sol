// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {IEulerSwapFactory} from "./interfaces/IEulerSwapFactory.sol";
import {IEulerSwapRegistry} from "./interfaces/IEulerSwapRegistry.sol";
import {IPerspective} from "./interfaces/IPerspective.sol";
import {SwapLib} from "./libraries/SwapLib.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

/// @title EulerSwapRegistry contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapRegistry is IEulerSwapRegistry, EVCUtil {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /// @dev Pool instances must be deployed by this factory
    address public immutable eulerSwapFactory;
    /// @dev Reentrancy guard, shares a storage slot with validVaultPerspective
    bool locked;
    /// @dev Perspective that checks whether vaults used by a pool are permitted by this registry
    address public validVaultPerspective;
    /// @dev Curator can set the minimum validity bond, update the valid vault perspective,
    /// and remove pools from the factory lists
    address public curator;
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

    event PoolRegistered(
        address indexed asset0,
        address indexed asset1,
        address indexed eulerAccount,
        address pool,
        IEulerSwap.StaticParams sParams,
        uint256 validityBond
    );
    event PoolUnregistered(address indexed asset0, address indexed asset1, address indexed eulerAccount, address pool);
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
    event CuratorTransferred(address indexed oldCurator, address indexed newCurator);
    event MinimumValidityBondUpdated(uint256 oldValue, uint256 newValue);
    event ValidVaultPerspectiveUpdated(address indexed oldPerspective, address indexed newPerspective);

    error Locked();
    error Unauthorized();
    error NotEulerSwapPool();
    error OldOperatorStillInstalled();
    error OperatorNotInstalled();
    error InvalidVaultImplementation();
    error SliceOutOfBounds();
    error InsufficientValidityBond();
    error ChallengeNoBondAvailable();
    error ChallengeBadAssets();
    error ChallengeLiquidityDeferred();
    error ChallengeMissingBond();
    error ChallengeUnauthorized();
    error ChallengeSwapSucceeded();
    error ChallengeSwapNotLiquidityFailure();

    error E_AccountLiquidity(); // From EVK

    constructor(address evc, address eulerSwapFactory_, address validVaultPerspective_, address curator_)
        EVCUtil(evc)
    {
        eulerSwapFactory = eulerSwapFactory_;
        validVaultPerspective = validVaultPerspective_;
        curator = curator_;
    }

    modifier nonReentrant() {
        require(!locked, Locked());
        locked = true;
        _;
        locked = false;
    }

    /// @inheritdoc IEulerSwapRegistry
    function registerPool(address poolAddr) external payable nonReentrant {
        require(IEulerSwapFactory(eulerSwapFactory).deployedPools(poolAddr), NotEulerSwapPool());
        IEulerSwap pool = IEulerSwap(poolAddr);
        IEulerSwap.StaticParams memory sParams = pool.getStaticParams();

        require(_msgSender() == sParams.eulerAccount, Unauthorized());

        require(isValidVault(sParams.supplyVault0) && isValidVault(sParams.supplyVault1), InvalidVaultImplementation());
        require(sParams.borrowVault0 == address(0) || isValidVault(sParams.borrowVault0), InvalidVaultImplementation());
        require(sParams.borrowVault1 == address(0) || isValidVault(sParams.borrowVault1), InvalidVaultImplementation());

        require(msg.value >= minimumValidityBond, InsufficientValidityBond());

        uninstall(sParams.eulerAccount, sParams.eulerAccount, false);

        require(evc.isAccountOperatorAuthorized(sParams.eulerAccount, address(pool)), OperatorNotInstalled());

        (address asset0, address asset1) = pool.getAssets();

        installedPools[sParams.eulerAccount] = address(pool);
        validityBonds[address(pool)] = msg.value;

        allPools.add(address(pool));
        poolMap[asset0][asset1].add(address(pool));

        emit PoolRegistered(asset0, asset1, sParams.eulerAccount, address(pool), sParams, msg.value);
    }

    /// @inheritdoc IEulerSwapRegistry
    function unregisterPool() external nonReentrant {
        address eulerAccount = _msgSender();
        uninstall(eulerAccount, eulerAccount, false);
    }

    modifier onlyCurator() {
        require(_msgSender() == curator, Unauthorized());
        _;
    }

    /// @inheritdoc IEulerSwapRegistry
    function curatorUnregisterPool(address pool, address bondReceiver) external onlyCurator nonReentrant {
        address eulerAccount = IEulerSwap(pool).getStaticParams().eulerAccount;
        if (bondReceiver == address(0)) bondReceiver = eulerAccount;
        uninstall(eulerAccount, bondReceiver, true);
    }

    /// @inheritdoc IEulerSwapRegistry
    function transferCurator(address newCurator) external onlyCurator nonReentrant {
        emit CuratorTransferred(curator, newCurator);
        curator = newCurator;
    }

    /// @inheritdoc IEulerSwapRegistry
    function setMinimumValidityBond(uint256 newMinimum) external onlyCurator nonReentrant {
        emit MinimumValidityBondUpdated(minimumValidityBond, newMinimum);
        minimumValidityBond = newMinimum;
    }

    /// @inheritdoc IEulerSwapRegistry
    function setValidVaultPerspective(address newPerspective) external onlyCurator nonReentrant {
        emit ValidVaultPerspectiveUpdated(validVaultPerspective, newPerspective);
        validVaultPerspective = newPerspective;
    }

    /// @inheritdoc IEulerSwapRegistry
    function challengePool(
        address poolAddr,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        bool exactIn,
        address recipient
    ) external nonReentrant {
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
            require(
                bytes4(error) == E_AccountLiquidity.selector || bytes4(error) == SwapLib.HookError.selector,
                ChallengeSwapNotLiquidityFailure()
            );
        }

        uint256 bondAmount = validityBonds[poolAddr];
        emit PoolChallenged(msg.sender, poolAddr, tokenIn, tokenOut, amount, exactIn, bondAmount, recipient);

        uninstall(eulerAccount, recipient, true);
    }

    /// @dev Function invoked by challengePool so that errors can be caught. Not intended
    /// to be called by the outside world.
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

    /// @inheritdoc IEulerSwapRegistry
    function poolByEulerAccount(address eulerAccount) external view returns (address) {
        return installedPools[eulerAccount];
    }

    /// @inheritdoc IEulerSwapRegistry
    function validityBond(address pool) external view returns (uint256) {
        return validityBonds[pool];
    }

    /// @inheritdoc IEulerSwapRegistry
    function poolsLength() external view returns (uint256) {
        return allPools.length();
    }

    /// @inheritdoc IEulerSwapRegistry
    function poolsSlice(uint256 start, uint256 end) external view returns (address[] memory) {
        return getSlice(allPools, start, end);
    }

    /// @inheritdoc IEulerSwapRegistry
    function pools() external view returns (address[] memory) {
        return allPools.values();
    }

    /// @inheritdoc IEulerSwapRegistry
    function poolsByPairLength(address asset0, address asset1) external view returns (uint256) {
        return poolMap[asset0][asset1].length();
    }

    /// @inheritdoc IEulerSwapRegistry
    function poolsByPairSlice(address asset0, address asset1, uint256 start, uint256 end)
        external
        view
        returns (address[] memory)
    {
        return getSlice(poolMap[asset0][asset1], start, end);
    }

    /// @inheritdoc IEulerSwapRegistry
    function poolsByPair(address asset0, address asset1) external view returns (address[] memory) {
        return poolMap[asset0][asset1].values();
    }

    /// @notice Calls a perspective contract to determine if a vault is acceptable.
    /// @param v Candidate vault address
    function isValidVault(address v) internal view returns (bool) {
        return IPerspective(validVaultPerspective).isVerified(v);
    }

    /// @notice Uninstalls the pool associated with the given Euler account
    /// @dev This function removes the pool from the registry's tracking and emits a PoolUnregistered event
    /// @dev The function checks if the operator is still installed and reverts if it is
    /// @dev If no pool exists for the account, the function returns without any action
    /// @param eulerAccount The address of the Euler account whose pool should be uninstalled
    /// @param bondRecipient Where the bond should be sent.
    /// @param forced Whether this is a forced uninstall, vs a user-requested uninstall
    function uninstall(address eulerAccount, address bondRecipient, bool forced) internal {
        address pool = installedPools[eulerAccount];
        if (pool == address(0)) return;

        if (!forced) {
            require(!evc.isAccountOperatorAuthorized(eulerAccount, pool), OldOperatorStillInstalled());
            delete installedPools[eulerAccount];
        }

        (address asset0, address asset1) = IEulerSwap(pool).getAssets();

        allPools.remove(pool);
        poolMap[asset0][asset1].remove(pool);

        redeemValidityBond(pool, bondRecipient);

        emit PoolUnregistered(asset0, asset1, eulerAccount, pool);
    }

    /// @notice Sends a pool's validity bond to a recipient.
    /// @param pool The EulerSwap instance's address
    /// @param recipient Who should receive the bond
    function redeemValidityBond(address pool, address recipient) internal returns (uint256 bondAmount) {
        bondAmount = validityBonds[pool];

        if (bondAmount != 0) {
            address owner = evc.getAccountOwner(recipient);
            if (owner != address(0)) recipient = owner;
            validityBonds[pool] = 0;
            (bool success,) = recipient.call{value: bondAmount}("");
            require(success, ChallengeMissingBond());
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
}
