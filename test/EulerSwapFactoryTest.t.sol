// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapFactory, IEulerSwapFactory} from "../src/EulerSwapFactory.sol";

contract EulerSwapFactoryTest is EulerSwapTestBase {
    EulerSwapFactory public eulerSwapFactory;

    uint256 minFee = 0.0000000000001e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(creator);
        eulerSwapFactory = new EulerSwapFactory();
    }

    function testDeployPool() public {
        uint256 allPoolsLengthBefore = eulerSwapFactory.allPoolsLength();

        vm.prank(creator);
        EulerSwap eulerSwap = EulerSwap(
            eulerSwapFactory.deployPool(
                IEulerSwapFactory.DeployParams(
                    address(eTST), address(eTST2), holder, 0, 1e18, 1e18, 0.4e18, 0.85e18, 50e18, 50e18
                )
            )
        );

        uint256 allPoolsLengthAfter = eulerSwapFactory.allPoolsLength();
        bytes32 poolKey = keccak256(
            abi.encode(
                eulerSwap.asset0(),
                eulerSwap.asset1(),
                eulerSwap.vault0(),
                eulerSwap.vault1(),
                eulerSwap.myAccount(),
                eulerSwap.feeMultiplier(),
                eulerSwap.priceX(),
                eulerSwap.priceY(),
                eulerSwap.concentrationX(),
                eulerSwap.concentrationY()
            )
        );

        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);
        assertEq(eulerSwapFactory.getPool(poolKey), address(eulerSwap));
        assertEq(eulerSwapFactory.getPool(poolKey), address(eulerSwap));

        address[] memory poolsList = eulerSwapFactory.getAllPoolsListSlice(0, type(uint256).max);
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], address(eulerSwap));
        assertEq(eulerSwapFactory.allPools(0), address(eulerSwap));

        vm.prank(creator);
        vm.expectRevert(EulerSwapFactory.AlreadyDeployed.selector);
        eulerSwapFactory.deployPool(
            IEulerSwapFactory.DeployParams(
                address(eTST), address(eTST2), holder, 0, 1e18, 1e18, 0.4e18, 0.85e18, 50e18, 50e18
            )
        );
    }

    function testInvalidGetAllPoolsListSliceQuery() public {
        vm.expectRevert(EulerSwapFactory.InvalidQuery.selector);
        eulerSwapFactory.getAllPoolsListSlice(1, 0);
    }

    function testDeployWithAssetsOutOfOrderOrEqual() public {
        vm.prank(creator);
        vm.expectRevert(EulerSwap.AssetsOutOfOrderOrEqual.selector);
        eulerSwapFactory.deployPool(
            IEulerSwapFactory.DeployParams(
                address(eTST), address(eTST), holder, 0, 1e18, 1e18, 0.4e18, 0.85e18, 50e18, 50e18
            )
        );
    }

    function testDeployWithBadFee() public {
        vm.prank(creator);
        vm.expectRevert(EulerSwap.BadParam.selector);
        eulerSwapFactory.deployPool(
            IEulerSwapFactory.DeployParams(
                address(eTST), address(eTST2), holder, 1e18, 1e18, 1e18, 0.4e18, 0.85e18, 50e18, 50e18
            )
        );
    }
}
