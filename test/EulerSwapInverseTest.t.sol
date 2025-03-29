// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {UD60x18, ud} from "prb-math/UD60x18.sol";

contract EulerSwapScenarioTest is Test {
    /// @dev EulerSwap curve definition
    /// Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            require(v <= type(uint248).max, "HELP");
            return y0 + (v + (py - 1)) / py;
        }
    }

    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        // components of quadratic equation
        int256 B = int256((py * (y - y0) + (px - 1)) / px) - (2 * int256(c) - int256(1e18)) * int256(x0) / 1e18;
        uint256 C = ((1e18 - c) * x0 * x0 + (1e36 - 1)) / 1e36; // upper bound of 1e28 for x0 means this is safe
        uint256 fourAC = Math.mulDiv(4 * c, C, 1, Math.Rounding.Ceil);

        // solve for the square root
        uint256 absB = abs(B);
        uint256 squaredB = Math.mulDiv(absB, absB, 1, Math.Rounding.Ceil);
        uint256 discriminant = squaredB + fourAC; // keep in 1e36 scale for increased precision ahead of sqrt
        uint256 sqrt = Math.sqrt(discriminant); // drop back to 1e18 scale
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;

        if (B <= 0) {
            return Math.mulDiv(absB + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 2;
        } else {
            return Math.mulDiv(2 * C, 1e18, absB + sqrt, Math.Rounding.Ceil) + 2;
        }
    }

    function verify(uint256 x, uint256 y, uint256 x0, uint256 y0, uint256 px, uint256 py, uint256 cx, uint256 cy)
        internal
        pure
        returns (bool)
    {
        if (x > type(uint112).max || y > type(uint112).max) return false;
        if (x >= x0) {
            if (y >= y0) return true;
            return x >= f(y, py, px, y0, x0, cy);
        } else {
            if (y < y0) return false;
            return y >= f(x, px, py, x0, y0, cx);
        }
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function binarySearch(
        uint256 y,
        uint256 px,
        uint256 py,
        uint256 x0,
        uint256 y0,
        uint256 c,
        uint256 xMin,
        uint256 xMax
    ) internal pure returns (uint256) {
        if (xMin < 1) {
            xMin = 1;
        }
        while (xMin < xMax) {
            uint256 xMid = (xMin + xMax) / 2;
            uint256 fxMid = f(xMid, px, py, x0, y0, c);
            if (y >= fxMid) {
                xMax = xMid;
            } else {
                xMin = xMid + 1;
            }
        }
        if (y < f(xMin, px, py, x0, y0, c)) {
            xMin += 1;
        }
        return xMin;
    }

    function test_fInverse() public view {
        // Params
        uint256 px = 1e18;
        uint256 py = 20e18;
        uint256 x0 = 1e20;
        uint256 y0 = 1e20;
        uint256 cx = 0.4e18;
        uint256 cy = 0.6e18;
        console.log("px", px);
        console.log("py", py);
        console.log("x0", x0);
        console.log("y0", y0);
        console.log("cx", cx);
        console.log("cy", cy);

        // Note without -2 in the max bound, f() sometimes fails when x gets too close to centre.
        // Note small x values lead to large y-values, which causes problems for both f() and fInverse(), so we cap it here
        uint256 x = x0 / 10;

        uint256 y = f(x, px, py, x0, y0, cx);
        uint256 gasBefore = gasleft();
        uint256 xCalc = fInverse(y, px, py, x0, y0, cx);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used:", gasUsed);
        console.log("x     ", x);
        console.log("xCalc ", xCalc);
        console.log("y     ", y);

        if (x < type(uint112).max && y < type(uint112).max) {
            assert(verify(xCalc, y, x0, y0, px, py, cx, cy));
        }
    }

    function test_fuzzfInverse(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        public
        pure
    {
        // Params
        px = 1e18;
        py = bound(py, 1, 1e36);
        x0 = 1e28;
        y0 = bound(y0, 0, 1e28);
        cx = bound(cx, 1, 1e18);
        cy = bound(cy, 1, 1e18);
        console.log("px", px);
        console.log("py", py);
        console.log("x0", x0);
        console.log("y0", y0);
        console.log("cx", cx);
        console.log("cy", cy);

        // Note without -2 in the max bound, f() sometimes fails when x gets too close to centre.
        // Note small x values lead to large y-values, which causes problems for both f() and fInverse(), so we cap it here
        x = bound(x, 0.5e18, x0 - 2);

        uint256 y = f(x, px, py, x0, y0, cx);
        uint256 xCalc = fInverse(y, px, py, x0, y0, cx);
        uint256 yCalc = f(xCalc, px, py, x0, y0, cx);
        uint256 xBin = binarySearch(yCalc, px, py, x0, y0, cx, 1, x0);
        uint256 yBin = f(xBin, px, py, x0, y0, cx);
        console.log("x     ", x);
        console.log("xCalc ", xCalc);
        console.log("xBin  ", xBin);
        console.log("y     ", y);
        console.log("yCalc ", yCalc);
        console.log("yBin  ", yBin);

        if (x < type(uint112).max && y < type(uint112).max) {
            assert(verify(xCalc, y, x0, y0, px, py, cx, cy));
            assert(int256(xCalc) - int256(xBin) <= 3); // suspect this is 2 wei error in fInverse() + 1 wei error in f()
            assert(int256(yCalc) - int256(yBin) <= 3);
        }
    }
}
