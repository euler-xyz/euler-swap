// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {IEulerSwap} from "../src/interfaces/IEulerSwap.sol";
import {CurveLib} from "../src/libraries/CurveLib.sol";

contract CurveLibTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_fInverse() public pure {
        // Params
        uint256 px = 1e18;
        uint256 py = 1e18;
        uint256 x0 = 1e14;
        uint256 y0 = 1e14;
        uint256 cx = 1e18;

        // Use CurveLib.f to get a valid y
        uint256 x = 1;
        console.log("x    ", x);
        uint256 y = CurveLib.f(x, px, py, x0, y0, cx);
        console.log("y    ", y);
        uint256 xCalc = CurveLib.fInverse(y, px, py, x0, y0, cx);
        console.log("xCalc", xCalc);
        uint256 yCalc = CurveLib.f(xCalc, px, py, x0, y0, cx);
        console.log("yCalc", yCalc);
    }

    function test_fuzzfInverse(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        public
        pure
    {
        // Params
        px = 1;
        py = bound(py, 1, 1e24);
        x0 = bound(x0, 1, 1e28);
        y0 = bound(y0, 0, 1e28);
        cx = bound(cx, 0, 1e18 - 1); // FIXME: test for constant-sum
        cy = bound(cy, 0, 1e18);
        console.log("px", px);
        console.log("py", py);
        console.log("x0", x0);
        console.log("y0", y0);
        console.log("cx", cx);
        console.log("cy", cy);

        IEulerSwap.DynamicParams memory p = IEulerSwap.DynamicParams({
            equilibriumReserve0: uint112(x0),
            equilibriumReserve1: uint112(y0),
            minReserve0: 0,
            minReserve1: 0,
            priceX: uint80(px),
            priceY: uint80(py),
            concentrationX: uint64(cx),
            concentrationY: uint64(cy),
            fee0: 0,
            fee1: 0,
            expiration: 0,
            swapHookedOperations: 0,
            swapHook: address(0)
        });

        x = bound(x, 1, x0);

        uint256 y = CurveLib.f(x, px, py, x0, y0, cx);
        console.log("y    ", y);
        uint256 xCalc = CurveLib.fInverse(y, px, py, x0, y0, cx);
        console.log("xCalc", xCalc);
        uint256 yCalc = CurveLib.f(xCalc, px, py, x0, y0, cx);
        uint256 xBin = binarySearch(p, y, 1, x0);
        uint256 yBin = CurveLib.f(xBin, px, py, x0, y0, cx);
        console.log("x    ", x);
        console.log("xCalc", xCalc);
        console.log("xBin ", xBin);
        console.log("y    ", y);
        console.log("yCalc", yCalc);
        console.log("yBin ", yBin);

        if (x < type(uint112).max && y < type(uint112).max) {
            assert(CurveLib.verify(p, xCalc, y));
            console.log("Invariant passed");
            assert(xCalc - xBin <= 3 || y - yCalc <= 3); // suspect this is 2 wei error in fInverse() + 1 wei error in f()
            console.log("Margin error passed");
        }
    }

    function test_fuzzFEquillibrium(uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        public
        pure
    {
        // Params
        px = bound(px, 1, 1e24);
        py = bound(py, 1, 1e24);
        x0 = bound(x0, 1, 1e28);
        y0 = bound(y0, 1, 1e28);
        cx = bound(cx, 0, 1e18);
        cy = bound(cy, 0, 1e18);

        uint256 y = CurveLib.f(x0, px, py, x0, y0, cx);
        uint256 x = CurveLib.f(y0, py, px, y0, x0, cy);

        if (x < type(uint112).max && y < type(uint112).max) {
            assertEq(y, y0);
            assertEq(x, x0);
        }
    }

    /// @dev Less efficient method to compute fInverse. Useful for differential fuzzing.
    function binarySearch(IEulerSwap.DynamicParams memory p, uint256 newReserve1, uint256 xMin, uint256 xMax)
        internal
        pure
        returns (uint256)
    {
        if (xMin < 1) {
            xMin = 1;
        }
        while (xMin < xMax) {
            uint256 xMid = (xMin + xMax) / 2;
            uint256 fxMid =
                CurveLib.f(xMid, p.priceX, p.priceY, p.equilibriumReserve0, p.equilibriumReserve1, p.concentrationX);
            if (newReserve1 >= fxMid) {
                xMax = xMid;
            } else {
                xMin = xMid + 1;
            }
        }
        if (
            newReserve1
                < CurveLib.f(xMin, p.priceX, p.priceY, p.equilibriumReserve0, p.equilibriumReserve1, p.concentrationX)
        ) {
            xMin += 1;
        }
        return xMin;
    }
}
