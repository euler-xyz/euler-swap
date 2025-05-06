// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManagerDeployer} from "./utils/PoolManagerDeployer.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {EulerSwapTestBase, IEulerSwap, IEVC, EulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapFactory, IEulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {EulerSwap} from "../src/EulerSwap.sol";
import {MetaProxyDeployer} from "../src/utils/MetaProxyDeployer.sol";

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
        returns (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState)
    {
        poolParams = getEulerSwapParams(1e18, 1e18, 1e18, 1e18, 0.4e18, 0.85e18, 0, 0, address(0));
        initialState = IEulerSwap.InitialState({currReserve0: 1e18, currReserve1: 1e18});
    }

    function mineSalt(IEulerSwap.Params memory poolParams) internal view returns (address hookAddress, bytes32 salt) {
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        );
        bytes memory creationCode = MetaProxyDeployer.creationCodeMetaProxy(eulerSwapImpl, abi.encode(poolParams));
        (hookAddress, salt) = HookMiner.find(address(eulerSwapFactory), flags, creationCode);
    }

    function mineBadSalt(IEulerSwap.Params memory poolParams)
        internal
        view
        returns (address hookAddress, bytes32 salt)
    {
        // missing BEFORE_ADD_LIQUIDITY_FLAG
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.BEFORE_DONATE_FLAG
        );
        bytes memory creationCode = MetaProxyDeployer.creationCodeMetaProxy(eulerSwapImpl, abi.encode(poolParams));
        (hookAddress, salt) = HookMiner.find(address(eulerSwapFactory), flags, creationCode);
    }

    function testDifferingAddressesSameSalt() public view {
        (IEulerSwap.Params memory poolParams,) = getBasicParams();

        address a1 = eulerSwapFactory.computePoolAddress(poolParams, bytes32(0));

        poolParams.eulerAccount = address(123);

        address a2 = eulerSwapFactory.computePoolAddress(poolParams, bytes32(0));

        assert(a1 != a2);
    }

    function testDeployPool() public {
        uint256 allPoolsLengthBefore = eulerSwapFactory.poolsLength();

        // test when new pool not set as operator

        (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState) = getBasicParams();

        (address hookAddress, bytes32 salt) = mineSalt(poolParams);

        address predictedAddress = eulerSwapFactory.computePoolAddress(poolParams, salt);
        assertEq(hookAddress, predictedAddress);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, initialState, salt))
        });

        vm.prank(holder);
        vm.expectRevert(EulerSwapFactory.OperatorNotInstalled.selector);
        evc.batch(items);

        // success test

        items = new IEVC.BatchItem[](2);

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
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, initialState, salt))
        });

        vm.prank(holder);
        evc.batch(items);

        address eulerSwap = eulerSwapFactory.poolByEulerAccount(holder);

        assertEq(address(EulerSwap(eulerSwap).poolManager()), address(poolManager));

        uint256 allPoolsLengthAfter = eulerSwapFactory.poolsLength();
        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);

        address[] memory poolsList = eulerSwapFactory.pools();
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], eulerSwap);
        assertEq(poolsList[0], address(eulerSwap));

        // revert when attempting to deploy a new pool (with a different salt)
        poolParams.fee = 1;
        (address newHookAddress, bytes32 newSalt) = mineSalt(poolParams);
        assertNotEq(newHookAddress, hookAddress);
        assertNotEq(newSalt, salt);

        items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, initialState, newSalt))
        });

        vm.prank(holder);
        vm.expectRevert(EulerSwapFactory.OldOperatorStillInstalled.selector);
        evc.batch(items);
    }

    function testBadSalt() public {
        (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState) = getBasicParams();
        (address hookAddress, bytes32 salt) = mineBadSalt(poolParams);

        vm.prank(holder);
        evc.setAccountOperator(holder, hookAddress, true);

        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, hookAddress));
        vm.prank(holder);
        eulerSwapFactory.deployPool(poolParams, initialState, salt);
    }

    function testInvalidPoolsSliceOutOfBounds() public {
        vm.expectRevert(EulerSwapFactory.SliceOutOfBounds.selector);
        eulerSwapFactory.poolsSlice(1, 0);
    }

    function testDeployWithInvalidVaultImplementation() public {
        bytes32 salt = bytes32(uint256(1234));
        (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState) = getBasicParams();

        // Create a fake vault that's not deployed by the factory
        address fakeVault = address(0x1234);
        poolParams.vault0 = fakeVault;
        poolParams.vault1 = address(eTST2);

        vm.prank(holder);
        vm.expectRevert(EulerSwapFactory.InvalidVaultImplementation.selector);
        eulerSwapFactory.deployPool(poolParams, initialState, salt);
    }

    function testDeployWithUnauthorizedCaller() public {
        bytes32 salt = bytes32(uint256(1234));
        (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState) = getBasicParams();

        // Call from a different address than the euler account
        vm.prank(address(0x1234));
        vm.expectRevert(EulerSwapFactory.Unauthorized.selector);
        eulerSwapFactory.deployPool(poolParams, initialState, salt);
    }

    function testDeployWithAssetsOutOfOrderOrEqual() public {
        (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState) = getBasicParams();
        (poolParams.vault0, poolParams.vault1) = (poolParams.vault1, poolParams.vault0);

        (address hookAddress, bytes32 salt) = mineSalt(poolParams);

        vm.prank(holder);
        evc.setAccountOperator(holder, hookAddress, true);

        vm.prank(holder);
        vm.expectRevert(EulerSwap.AssetsOutOfOrderOrEqual.selector);
        eulerSwapFactory.deployPool(poolParams, initialState, salt);
    }

    function testDeployWithBadFee() public {
        (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState) = getBasicParams();
        poolParams.fee = 1e18;

        (address hookAddress, bytes32 salt) = mineSalt(poolParams);

        vm.prank(holder);
        evc.setAccountOperator(holder, hookAddress, true);

        vm.prank(holder);
        vm.expectRevert(EulerSwap.BadParam.selector);
        eulerSwapFactory.deployPool(poolParams, initialState, salt);
    }

    function testPoolsByPair() public {
        // First deploy a pool
        (IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState) = getBasicParams();
        (address hookAddress, bytes32 salt) = mineSalt(poolParams);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);
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
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, initialState, salt))
        });

        vm.prank(holder);
        evc.batch(items);

        // Get the deployed pool and its assets
        address pool = eulerSwapFactory.poolByEulerAccount(holder);
        (address asset0, address asset1) = EulerSwap(pool).getAssets();

        // Test poolsByPairLength
        assertEq(eulerSwapFactory.poolsByPairLength(asset0, asset1), 1);

        // Test poolsByPairSlice
        address[] memory slice = eulerSwapFactory.poolsByPairSlice(asset0, asset1, 0, 1);
        assertEq(slice.length, 1);
        assertEq(slice[0], hookAddress);

        // Test poolsByPair
        address[] memory pools = eulerSwapFactory.poolsByPair(asset0, asset1);
        assertEq(pools.length, 1);
        assertEq(pools[0], hookAddress);
    }

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function test_multipleUninstalls() public {
        (IEulerSwap.Params memory params, IEulerSwap.InitialState memory initialState) = getBasicParams();

        // Deploy pool for Alice
        params.eulerAccount = holder = alice;
        (address alicePool, bytes32 aliceSalt) = mineSalt(params);

        vm.startPrank(alice);
        evc.setAccountOperator(alice, alicePool, true);
        eulerSwapFactory.deployPool(params, initialState, aliceSalt);

        // Deploy pool for Bob
        params.eulerAccount = holder = bob;
        (address bobPool, bytes32 bobSalt) = mineSalt(params);

        vm.startPrank(bob);
        evc.setAccountOperator(bob, bobPool, true);
        eulerSwapFactory.deployPool(params, initialState, bobSalt);

        {
            address[] memory ps = eulerSwapFactory.pools();
            assertEq(ps.length, 2);
            assertEq(ps[0], alicePool);
            assertEq(ps[1], bobPool);
        }

        {
            (address asset0, address asset1) = EulerSwap(alicePool).getAssets();
            address[] memory ps = eulerSwapFactory.poolsByPair(asset0, asset1);
            assertEq(ps.length, 2);
            assertEq(ps[0], alicePool);
            assertEq(ps[1], bobPool);
        }

        // Uninstall pool for Alice
        vm.startPrank(alice);
        evc.setAccountOperator(alice, alicePool, false);
        eulerSwapFactory.uninstallPool();

        {
            address[] memory ps = eulerSwapFactory.pools();
            assertEq(ps.length, 1);
            assertEq(ps[0], bobPool);
        }

        {
            (address asset0, address asset1) = EulerSwap(alicePool).getAssets();
            address[] memory ps = eulerSwapFactory.poolsByPair(asset0, asset1);
            assertEq(ps.length, 1);
            assertEq(ps[0], bobPool);
        }

        // Uninstalling pool for Bob reverts due to an OOB access of the allPools array
        vm.startPrank(bob);
        evc.setAccountOperator(bob, bobPool, false);
        eulerSwapFactory.uninstallPool();

        {
            address[] memory ps = eulerSwapFactory.pools();
            assertEq(ps.length, 0);
        }

        {
            (address asset0, address asset1) = EulerSwap(alicePool).getAssets();
            address[] memory ps = eulerSwapFactory.poolsByPair(asset0, asset1);
            assertEq(ps.length, 0);
        }
    }
}
