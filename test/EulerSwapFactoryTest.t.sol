// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, IEulerSwap, IEVC, EulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapFactory, IEulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapFactoryTest is EulerSwapTestBase {
    EulerSwapFactory public eulerSwapFactory;

    uint256 minFee = 0.0000000000001e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(creator);
        eulerSwapFactory = new EulerSwapFactory(address(evc));
    }

    function testDeployPool() public {
        uint256 allPoolsLengthBefore = eulerSwapFactory.allPoolsLength();

        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, 1e18, 1e18, 1e18, 1e18, 0);
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

        EulerSwap eulerSwap = EulerSwap(eulerSwapFactory.eulerAccountToPool(holder));

        uint256 allPoolsLengthAfter = eulerSwapFactory.allPoolsLength();
        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);

        address[] memory poolsList = eulerSwapFactory.getAllPoolsListSlice(0, type(uint256).max);
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], address(eulerSwap));
        assertEq(eulerSwapFactory.allPools(0), address(eulerSwap));

        items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(eulerSwapFactory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, bytes32(uint256(12345))))
        });

        vm.prank(holder);
        vm.expectRevert(EulerSwapFactory.OldOperatorStillInstalled.selector);
        evc.batch(items);
    }

    function testInvalidGetAllPoolsListSliceQuery() public {
        vm.expectRevert(EulerSwapFactory.InvalidQuery.selector);
        eulerSwapFactory.getAllPoolsListSlice(1, 0);
    }

    function testDeployWithAssetsOutOfOrderOrEqual() public {
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST), holder, 1e18, 1e18, 1e18, 1e18, 0);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        vm.prank(holder);
        vm.expectRevert(EulerSwap.AssetsOutOfOrderOrEqual.selector);
        eulerSwapFactory.deployPool(poolParams, curveParams, salt);
    }

    function testDeployWithBadFee() public {
        bytes32 salt = bytes32(uint256(1234));
        IEulerSwap.Params memory poolParams =
            IEulerSwap.Params(address(eTST), address(eTST2), holder, 1e18, 1e18, 1e18, 1e18, 1e18);
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams(0.4e18, 0.85e18, 1e18, 1e18);

        vm.prank(holder);
        vm.expectRevert(EulerSwap.BadParam.selector);
        eulerSwapFactory.deployPool(poolParams, curveParams, salt);
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

    function fInverse(
        uint256 y, 
        uint256 px, 
        uint256 py, 
        uint256 x0, 
        uint256 y0, 
        uint256 c
    ) public pure returns (uint256) {

        // A component of the quadratic formula: a = 2 * c
        uint256 A = 2 * c;

        // B component of the quadratic formula
        int256 B = int256((px * (y - y0) + py - 1) / py) 
                 - int256((x0 * (2 * c - 1e18) + 1e18 - 1) / 1e18); 

        // B^2 component, using FullMath for overflow safety
        uint256 absB = B < 0 ? uint256(-B) : uint256(B);
        uint256 squaredB = Math.mulDiv(absB, absB, 1e18) 
                         + (absB * absB % 1e18 == 0 ? 0 : 1); 

        // 4 * A * C component of the quadratic formula
        uint256 AC4 = Math.mulDiv(
            Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil), 
            Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil), 
            1e18, 
            Math.Rounding.Ceil
        );

        // Discriminant: b^2 + 4ac, scaled up to maintain precision
        uint256 discriminant = (squaredB + AC4) * 1e18;

        // Square root of the discriminant (rounded up)
        uint256 sqrt = Math.sqrt(discriminant);
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;

        // Compute and return x = fInverse(y) using the quadratic formula
        return Math.mulDiv(uint256(int256(sqrt) - B), 1e18, A, Math.Rounding.Ceil);
    }


    function testSwapScenarios() public {

    }

}
