// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {UD60x18, ud} from "prb-math/UD60x18.sol";

contract EulerSwapScenarioTest is Test {
    
    /// @dev EulerSwap curve definition
    /// Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function fEulerSwap(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            require(v <= type(uint248).max, "HELP");
            return y0 + (v + (py - 1)) / py;
        }
    }

    function fInverseEulerSwap(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        // components of quadratic equation
        uint256 A = c;
        int256 B =
            int256(Math.mulDiv(py, y - y0, px, Math.Rounding.Ceil)) - (2 * int256(c) - int256(1e18)) * int256(x0) / 1e18;
        uint256 squaredX0 = Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil);
        uint256 C = Math.mulDiv(1e18 - c, squaredX0, 1e18, Math.Rounding.Ceil);

        // solve for the square root
        uint256 absB = abs(B);
        uint256 squaredB = Math.mulDiv(absB, absB * 1e18, 1e18, Math.Rounding.Ceil);
        uint256 discriminant = uint256(int256(squaredB) + 4 * int256(A) * int256(C));
        uint256 sqrt = Math.sqrt(discriminant);
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
        
        if (B <= 0) {
            return Math.mulDiv(uint256(int256(sqrt) - B), 1e18, 2 * c, Math.Rounding.Ceil) + 2;
        } else {
            return Math.mulDiv(2 * C, 1e18, absB + sqrt, Math.Rounding.Ceil) + 2;
        }
    }

    function verifyEulerSwap(
        uint256 x,
        uint256 y,
        uint256 x0,
        uint256 y0,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) public view returns (bool) {
        if (x > type(uint112).max || y > type(uint112).max) return false;
        if (x >= x0) {
            if (y >= y0) return true;
            return x >= fEulerSwap(y, py, px, y0, x0, cy);
        } else {
            if (y < y0) return false;
            return y >= fEulerSwap(x, px, py, x0, y0, cx);
        }
    }

    function scaleUpX(uint256 x, uint256 x0) internal pure returns (uint256) {
        return Math.mulDiv(x, x0, 1e18);
    }

    function scaleDownY(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(py * 1e18, y - y0, x0 * px) + 1e18;
    }

    function verify(uint256 xNew, uint256 yNew, uint256 cx, uint256 cy) public view returns (bool) {
        if (xNew >= 1e18) {
            return xNew >= f(yNew, cy);
        } else {
            return yNew >= f(xNew, cx);
        }
    }

    function f(uint256 x, uint256 c) internal pure returns (uint256) {
        return Math.mulDiv(1e18 - c, 1e18, x, Math.Rounding.Ceil) + Math.mulDiv(c, 2e18 - x, 1e18, Math.Rounding.Ceil);
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function quadratic(uint256 y, uint256 c) internal pure returns (uint256) {
        int256 B = int256(y) - 2 * int256(c);
        int256 maxAC = 2 * int256(Math.sqrt(Math.mulDiv(c * 1e18, 1e18 - c, 1)));
        uint256 sqrt;
        if (B > maxAC) {
            sqrt = uint256(B);
        } else {
            uint256 absB = abs(B);
            uint256 squaredB = absB * absB;
            uint256 discriminant = squaredB + Math.mulDiv(4 * c, (1e18 - c) * 1e18, 1e18);
            sqrt = Math.sqrt(discriminant);
            sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
        }

        if (B < 0) {
            return Math.mulDiv(2 * c - y + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 2;
        } else {
            return Math.mulDiv(2 * (1e18 - c), 1e18, uint256(B) + sqrt, Math.Rounding.Ceil) + 2;
        }
    }

    // Note: second if statement fixes off-by-one error
    // if xMin == xMax - 1 and and y >= f(xMin, c) is true, then xMid = (xMin + xMax) / 2 = xMin and xMax = xMid = xMin, but we never tested xMax
    function binary(uint256 y, uint256 c, uint256 xMin, uint256 xMax) internal pure returns (uint256) {
        if (xMin < 1) {
            xMin = 1;
        }
        while (xMin < xMax) {
            uint256 xMid = (xMin + xMax) / 2;
            uint256 fxMid = f(xMid, c);
            if (y >= fxMid) {
                xMax = xMid;
            } else {
                xMin = xMid + 1;
            }
        }
        if (y < f(xMin, c)) {
            xMin += 1;
        }
        return xMin;
    }

    function binaryEulerSwap(
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
            uint256 fxMid = fEulerSwap(xMid, px, py, x0, y0, c);
            if (y >= fxMid) {
                xMax = xMid;
            } else {
                xMin = xMid + 1;
            }
        }
        if (y < fEulerSwap(xMin, px, py, x0, y0, c)) {
            xMin += 1;
        }
        return xMin;
    }

    function test_fuzzfInverse(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        public
    {
        // Params
        px = 1e18;
        py = bound(py, 1, 1e38);
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

        x = bound(x, 1e18, x0 - 2); // TODO: note that the -2 here is the tolerance in the fInverse function. Without this, f() fails when x gets too close to centre.        
        
        uint256 y = fEulerSwap(x, px, py, x0, y0, cx);        
        uint256 xCalc = fInverseEulerSwap(y, px, py, x0, y0, cx);
        uint256 yCalc = fEulerSwap(xCalc, px, py, x0, y0, cx);
        uint256 xBin = binaryEulerSwap(yCalc, px, py, x0, y0, cx, 1, x0);
        uint256 yBin = fEulerSwap(xBin, px, py, x0, y0, cx);
        console.log("x     ", x);
        console.log("xCalc ", xCalc);
        console.log("xBin  ", xBin);
        console.log("y     ", y);
        console.log("yCalc ", yCalc);
        console.log("yBin  ", yBin);
        
        if (x < type(uint112).max && y < type(uint112).max) {
            assert(verifyEulerSwap(xCalc, y, x0, y0, px, py, cx, cy));
            assert(abs(int256(xBin) - int256(xCalc)) <= 3); // suspect this is 2 wei error in fInverse() + 1 wei error in f()
            assert(abs(int256(yBin) - int256(yCalc)) <= 3);
        }
    }

}
