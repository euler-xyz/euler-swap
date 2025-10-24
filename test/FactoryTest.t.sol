// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManagerDeployer} from "./utils/PoolManagerDeployer.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {PerspectiveMock} from "./utils/PerspectiveMock.sol";
import {EulerSwapTestBase, IEulerSwap, IEVC, EulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapFactory, IEulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {EulerSwapRegistry} from "../src/EulerSwapRegistry.sol";
import {EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapManagement} from "../src/EulerSwapManagement.sol";
import {MetaProxyDeployer} from "../src/utils/MetaProxyDeployer.sol";

interface ImmutablePoolManager {
    function poolManager() external view returns (IPoolManager);
}

contract FactoryTest is EulerSwapTestBase {
    IPoolManager public poolManager;

    function setUp() public virtual override {
        super.setUp();

        poolManager = PoolManagerDeployer.deploy(address(this));

        deployEulerSwap(address(poolManager));

        assertEq(eulerSwapFactory.EVC(), address(evc));
    }

    function getBasicParams()
        internal
        view
        returns (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        )
    {
        (sParams, dParams) = getEulerSwapParams(1e18, 1e18, 1e18, 1e18, 0.4e18, 0.85e18, 0, address(0));
        initialState = IEulerSwap.InitialState({reserve0: 1e18, reserve1: 1e18});
    }

    function mineSalt(IEulerSwap.StaticParams memory sParams)
        internal
        view
        returns (address hookAddress, bytes32 salt)
    {
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        );
        bytes memory creationCode = eulerSwapFactory.creationCode(sParams);
        (hookAddress, salt) = HookMiner.find(address(eulerSwapFactory), flags, creationCode);
    }

    function mineBadSalt(IEulerSwap.StaticParams memory sParams)
        internal
        view
        returns (address hookAddress, bytes32 salt)
    {
        // missing BEFORE_ADD_LIQUIDITY_FLAG
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.BEFORE_DONATE_FLAG
        );
        bytes memory creationCode = eulerSwapFactory.creationCode(sParams);
        (hookAddress, salt) = HookMiner.find(address(eulerSwapFactory), flags, creationCode);
    }

    function testDifferingAddressesSameSalt() public view {
        (IEulerSwap.StaticParams memory sParams,,) = getBasicParams();

        address a1 = eulerSwapFactory.computePoolAddress(sParams, bytes32(0));

        sParams.eulerAccount = address(123);

        address a2 = eulerSwapFactory.computePoolAddress(sParams, bytes32(0));

        assert(a1 != a2);
    }

    function testDeployPool() public {
        uint256 allPoolsLengthBefore = eulerSwapRegistry.poolsLength();

        // test when new pool not set as operator

        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();

        (address hookAddress, bytes32 salt) = mineSalt(sParams);

        address predictedAddress = eulerSwapFactory.computePoolAddress(sParams, salt);
        assertEq(hookAddress, predictedAddress);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (sParams, dParams, initialState, salt))
        });

        vm.prank(holder);
        vm.expectRevert(EulerSwapRegistry.OperatorNotInstalled.selector);
        evc.batch(items);

        // success test

        items = new IEVC.BatchItem[](3);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, predictedAddress, true))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (sParams, dParams, initialState, salt))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapRegistry),
            value: 0,
            data: abi.encodeCall(EulerSwapRegistry.registerPool, (predictedAddress))
        });

        vm.expectEmit(true, true, true, true);
        emit EulerSwapFactory.PoolDeployed(address(assetTST), address(assetTST2), holder, predictedAddress, sParams);

        vm.expectEmit(true, true, true, true);
        emit EulerSwapRegistry.PoolRegistered(
            address(assetTST), address(assetTST2), holder, predictedAddress, sParams, 0
        );

        vm.prank(holder);
        evc.batch(items);

        address eulerSwap = eulerSwapRegistry.poolByEulerAccount(holder);

        assertEq(address(EulerSwap(eulerSwap).poolManager()), address(poolManager));

        uint256 allPoolsLengthAfter = eulerSwapRegistry.poolsLength();
        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);

        address[] memory poolsList = eulerSwapRegistry.pools();
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], eulerSwap);
        assertEq(poolsList[0], address(eulerSwap));

        // revert when attempting to register a new pool (with a different salt)
        sParams.feeRecipient = address(1);
        (address newHookAddress, bytes32 newSalt) = mineSalt(sParams);
        assertNotEq(newHookAddress, hookAddress);
        assertNotEq(newSalt, salt);

        items = new IEVC.BatchItem[](3);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, newHookAddress, true))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (sParams, dParams, initialState, newSalt))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapRegistry),
            value: 0,
            data: abi.encodeCall(EulerSwapRegistry.registerPool, (newHookAddress))
        });

        vm.prank(holder);
        vm.expectRevert(EulerSwapRegistry.OldOperatorStillInstalled.selector);
        evc.batch(items);
    }

    function testBadSalt() public {
        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();
        (address hookAddress, bytes32 salt) = mineBadSalt(sParams);

        vm.prank(holder);
        evc.setAccountOperator(holder, hookAddress, true);

        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, hookAddress));
        vm.prank(holder);
        eulerSwapFactory.deployPool(sParams, dParams, initialState, salt);
    }

    function testInvalidPoolsSliceOutOfBounds() public {
        vm.expectRevert(EulerSwapRegistry.SliceOutOfBounds.selector);
        eulerSwapRegistry.poolsSlice(1, 0);
    }

    function testDeployWithInvalidVaultImplementation() public {
        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();

        (address hookAddress, bytes32 salt) = mineSalt(sParams);

        // Blacklist one of the vaults
        validVaultPerspective.setBlacklist(address(eTST), true);

        vm.prank(holder);
        evc.setAccountOperator(holder, hookAddress, true);

        vm.prank(holder);
        eulerSwapFactory.deployPool(sParams, dParams, initialState, salt);

        vm.prank(holder);
        vm.expectRevert(EulerSwapRegistry.InvalidVaultImplementation.selector);
        eulerSwapRegistry.registerPool(hookAddress);

        // Switch to a new perspective where it's not blacklisted

        address newPerspective = address(new PerspectiveMock());
        vm.prank(curator);
        eulerSwapRegistry.setValidVaultPerspective(newPerspective);

        vm.prank(holder);
        eulerSwapRegistry.registerPool(hookAddress);
    }

    function testDeployWithUnauthorizedCaller() public {
        bytes32 salt = bytes32(uint256(1234));
        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();

        // Call from a different address than the euler account
        vm.prank(address(0x1234));
        vm.expectRevert(EulerSwapFactory.Unauthorized.selector);
        eulerSwapFactory.deployPool(sParams, dParams, initialState, salt);
    }

    function testDeployWithAssetsOutOfOrderOrEqual() public {
        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();
        (sParams.supplyVault0, sParams.supplyVault1) = (sParams.supplyVault1, sParams.supplyVault0);
        (sParams.borrowVault0, sParams.borrowVault1) = (sParams.borrowVault1, sParams.borrowVault0);

        (address hookAddress, bytes32 salt) = mineSalt(sParams);

        vm.prank(holder);
        evc.setAccountOperator(holder, hookAddress, true);

        vm.prank(holder);
        vm.expectRevert(EulerSwapManagement.AssetsOutOfOrderOrEqual.selector);
        eulerSwapFactory.deployPool(sParams, dParams, initialState, salt);
    }

    function testDeployWithBadFee() public {
        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();
        dParams.fee0 = 1e18 + 1;

        (address hookAddress, bytes32 salt) = mineSalt(sParams);

        vm.prank(holder);
        evc.setAccountOperator(holder, hookAddress, true);

        vm.prank(holder);
        vm.expectRevert(EulerSwapManagement.BadDynamicParam.selector);
        eulerSwapFactory.deployPool(sParams, dParams, initialState, salt);
    }

    function testRegisterInvalidPool() public {
        vm.expectRevert(EulerSwapRegistry.NotEulerSwapPool.selector);
        eulerSwapRegistry.registerPool(address(9999));
    }

    function testPoolsByPair() public {
        // First deploy a pool
        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();
        (address hookAddress, bytes32 salt) = mineSalt(sParams);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](3);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, hookAddress, true))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (sParams, dParams, initialState, salt))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapRegistry),
            value: 0,
            data: abi.encodeCall(EulerSwapRegistry.registerPool, (hookAddress))
        });

        vm.prank(holder);
        evc.batch(items);

        // Get the deployed pool and its assets
        address pool = eulerSwapRegistry.poolByEulerAccount(holder);
        (address asset0, address asset1) = EulerSwap(pool).getAssets();

        // Test poolsByPairLength
        assertEq(eulerSwapRegistry.poolsByPairLength(asset0, asset1), 1);

        // Test poolsByPairSlice
        address[] memory slice = eulerSwapRegistry.poolsByPairSlice(asset0, asset1, 0, 1);
        assertEq(slice.length, 1);
        assertEq(slice[0], hookAddress);

        // Test poolsByPair
        address[] memory pools = eulerSwapRegistry.poolsByPair(asset0, asset1);
        assertEq(pools.length, 1);
        assertEq(pools[0], hookAddress);
    }

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function test_multipleUninstalls() public {
        (
            IEulerSwap.StaticParams memory sParams,
            IEulerSwap.DynamicParams memory dParams,
            IEulerSwap.InitialState memory initialState
        ) = getBasicParams();

        // Deploy pool for Alice
        sParams.eulerAccount = holder = alice;
        (address alicePool, bytes32 aliceSalt) = mineSalt(sParams);

        vm.startPrank(alice);
        evc.setAccountOperator(alice, alicePool, true);
        eulerSwapFactory.deployPool(sParams, dParams, initialState, aliceSalt);
        eulerSwapRegistry.registerPool(alicePool);

        // Deploy pool for Bob
        sParams.eulerAccount = holder = bob;
        (address bobPool, bytes32 bobSalt) = mineSalt(sParams);

        vm.startPrank(bob);
        evc.setAccountOperator(bob, bobPool, true);
        eulerSwapFactory.deployPool(sParams, dParams, initialState, bobSalt);
        eulerSwapRegistry.registerPool(bobPool);

        {
            address[] memory ps = eulerSwapRegistry.pools();
            assertEq(ps.length, 2);
            assertEq(ps[0], alicePool);
            assertEq(ps[1], bobPool);
        }

        {
            (address asset0, address asset1) = EulerSwap(alicePool).getAssets();
            address[] memory ps = eulerSwapRegistry.poolsByPair(asset0, asset1);
            assertEq(ps.length, 2);
            assertEq(ps[0], alicePool);
            assertEq(ps[1], bobPool);
        }

        assertTrue(EulerSwap(alicePool).isInstalled());

        // Unregister pool for Alice
        vm.startPrank(alice);
        evc.setAccountOperator(alice, alicePool, false);

        vm.expectEmit(true, true, true, true);
        emit EulerSwapRegistry.PoolUnregistered(address(assetTST), address(assetTST2), alice, alicePool);
        eulerSwapRegistry.unregisterPool();

        assertFalse(EulerSwap(alicePool).isInstalled());

        {
            address[] memory ps = eulerSwapRegistry.pools();
            assertEq(ps.length, 1);
            assertEq(ps[0], bobPool);
        }

        {
            (address asset0, address asset1) = EulerSwap(alicePool).getAssets();
            address[] memory ps = eulerSwapRegistry.poolsByPair(asset0, asset1);
            assertEq(ps.length, 1);
            assertEq(ps[0], bobPool);
        }

        vm.startPrank(bob);
        evc.setAccountOperator(bob, bobPool, false);
        eulerSwapRegistry.unregisterPool();

        {
            address[] memory ps = eulerSwapRegistry.pools();
            assertEq(ps.length, 0);
        }

        {
            (address asset0, address asset1) = EulerSwap(alicePool).getAssets();
            address[] memory ps = eulerSwapRegistry.poolsByPair(asset0, asset1);
            assertEq(ps.length, 0);
        }

        // Register Bob's pool again

        vm.startPrank(bob);
        evc.setAccountOperator(bob, bobPool, true);
        eulerSwapRegistry.registerPool(bobPool);

        {
            address[] memory ps = eulerSwapRegistry.pools();
            assertEq(ps.length, 1);
            assertEq(ps[0], bobPool);
        }
    }
}
