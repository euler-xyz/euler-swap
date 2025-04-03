// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, IEulerSwap, IEVC, EulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapFactory, IEulerSwapFactory} from "../src/EulerSwapFactory.sol";

contract EulerSwapFactoryTest is EulerSwapTestBase {
    EulerSwapFactory public eulerSwapFactory;

    uint256 minFee = 0.0000000000001e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(creator);
        eulerSwapFactory = new EulerSwapFactory(address(evc), address(factory), address(this));

        assertEq(eulerSwapFactory.EVC(), address(evc));
    }

    function testDeployPool() public {
        uint256 allPoolsLengthBefore = eulerSwapFactory.poolsLength();

        // test when new pool not set as operator

        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, address(this), 1e18, 1e18, 1e18, 1e18, 0, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        address predictedAddress = predictPoolAddress(address(eulerSwapFactory), poolParams, curveParams, salt);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, salt))
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
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, salt))
        });

        vm.prank(holder);
        evc.batch(items);

        address eulerSwap = eulerSwapFactory.poolByEulerAccount(holder);

        uint256 allPoolsLengthAfter = eulerSwapFactory.poolsLength();
        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);

        address[] memory poolsList = eulerSwapFactory.pools();
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], eulerSwap);
        assertEq(poolsList[0], address(eulerSwap));

        // test when deploying second pool while old pool is still set as operator

        salt = bytes32(uint256(12345));
        predictedAddress = predictPoolAddress(address(eulerSwapFactory), poolParams, curveParams, salt);
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
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, salt))
        });

        vm.prank(holder);
        vm.expectRevert(EulerSwapFactory.OldOperatorStillInstalled.selector);
        evc.batch(items);

        // test deploying new pool for same assets pair as old one
        address oldPool = eulerSwapFactory.poolByEulerAccount(holder);
        salt = bytes32(uint256(123456));
        predictedAddress = predictPoolAddress(address(eulerSwapFactory), poolParams, curveParams, salt);

        items = new IEVC.BatchItem[](3);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, oldPool, false))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, predictedAddress, true))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, salt))
        });

        vm.prank(holder);
        evc.batch(items);

        address pool = eulerSwapFactory.poolByEulerAccount(holder);
        assertEq(pool, predictedAddress);

        // test deploying new pool for different assets pair as old one
        oldPool = eulerSwapFactory.poolByEulerAccount(holder);
        poolParams = IEulerSwap.Params(address(eTST), address(eTST3), holder, address(this), 1e18, 1e18, 1e18, 1e18, 0, 0);

        salt = bytes32(uint256(1234567));
        predictedAddress = predictPoolAddress(address(eulerSwapFactory), poolParams, curveParams, salt);

        items = new IEVC.BatchItem[](3);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, oldPool, false))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, predictedAddress, true))
        });
        items[2] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, salt))
        });

        vm.prank(holder);
        evc.batch(items);

        pool = eulerSwapFactory.poolByEulerAccount(holder);
        assertEq(pool, predictedAddress);
    }

    function testInvalidPoolsSliceOutOfBounds() public {
        vm.expectRevert(EulerSwapFactory.SliceOutOfBounds.selector);
        eulerSwapFactory.poolsSlice(1, 0);
    }

    function testDeployWithInvalidVaultImplementation() public {
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, address(this), 1e18, 1e18, 1e18, 1e18, 0, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        // Create a fake vault that's not deployed by the factory
        address fakeVault = address(0x1234);
        poolParams.vault0 = fakeVault;
        poolParams.vault1 = address(eTST2);

        vm.prank(holder);
        vm.expectRevert(EulerSwapFactory.InvalidVaultImplementation.selector);
        eulerSwapFactory.deployPool(poolParams, curveParams, salt);
    }

    function testDeployWithUnauthorizedCaller() public {
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, address(this), 1e18, 1e18, 1e18, 1e18, 0, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        // Call from a different address than the euler account
        vm.prank(address(0x1234));
        vm.expectRevert(EulerSwapFactory.Unauthorized.selector);
        eulerSwapFactory.deployPool(poolParams, curveParams, salt);
    }

    function testDeployWithAssetsOutOfOrderOrEqual() public {
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST), holder, address(this), 1e18, 1e18, 1e18, 1e18, 0, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        vm.prank(holder);
        vm.expectRevert(EulerSwap.AssetsOutOfOrderOrEqual.selector);
        eulerSwapFactory.deployPool(poolParams, curveParams, salt);
    }

    function testDeployWithBadFee() public {
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, address(this), 1e18, 1e18, 1e18, 1e18, 1e18, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        vm.prank(holder);
        vm.expectRevert(EulerSwap.BadParam.selector);
        eulerSwapFactory.deployPool(poolParams, curveParams, salt);
    }

    function testPoolsByPair() public {
        // First deploy a pool
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, address(this), 1e18, 1e18, 1e18, 1e18, 0, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        address predictedAddress = predictPoolAddress(address(eulerSwapFactory), poolParams, curveParams, salt);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);
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
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, salt))
        });

        vm.prank(holder);
        evc.batch(items);

        // Get the deployed pool and its assets
        address pool = eulerSwapFactory.poolByEulerAccount(holder);
        address asset0 = EulerSwap(pool).asset0();
        address asset1 = EulerSwap(pool).asset1();

        // Test poolsByPairLength
        assertEq(eulerSwapFactory.poolsByPairLength(asset0, asset1), 1);

        // Test poolsByPairSlice
        address[] memory slice = eulerSwapFactory.poolsByPairSlice(asset0, asset1, 0, 1);
        assertEq(slice.length, 1);
        assertEq(slice[0], predictedAddress);

        // Test poolsByPair
        address[] memory pools = eulerSwapFactory.poolsByPair(asset0, asset1);
        assertEq(pools.length, 1);
        assertEq(pools[0], predictedAddress);
    }

    function testComputePoolAddress() public view {
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, address(this), 1e18, 1e18, 1e18, 1e18, 0, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        address predictedAddress = eulerSwapFactory.computePoolAddress(poolParams, curveParams, salt);
        assertEq(predictedAddress, predictPoolAddress(address(eulerSwapFactory), poolParams, curveParams, salt));
    }

    function predictPoolAddress(
        address factoryAddress,
        IEulerSwap.Params memory poolParams,
        IEulerSwap.CurveParams memory curveParams,
        bytes32 salt
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            factoryAddress,
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
}
