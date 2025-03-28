// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import { PRBMathUD60x18 } from "prb-math/PRBMathUD60x18.sol";

contract EulerSwapScenarioTest is Test {
    
    /// @dev EulerSwap curve definition
    /// Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function fEulerSwap(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            require(v <= type(uint248).max, "HELP");
            return y0 + (v + (py - 1)) / py;
        }
    }

    function fInverseEulerSwap(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        int256 B = int256(Math.mulDiv(py, y - y0, px, Math.Rounding.Ceil)) - (2 * int256(c) - int256(1e18)) * int256(x0) / 1e18;
        uint256 absB = abs(B);
        uint256 squaredB = Math.mulDiv(absB, absB * 1e18, 1e18);
        uint256 squaredX0 = Math.mulDiv(x0, x0, 1e18);        
        uint256 C = Math.mulDiv(uint256(int256(1e18) - int256(c)), squaredX0, 1e18);
        uint256 discriminant = uint256(int256(squaredB) + 4 * int256(c) * int256(C));
        uint256 sqrt = Math.sqrt(discriminant);
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
        if (B < 0) {
            return Math.mulDiv(uint256(int256(sqrt) - B), 1e18, 2 * c, Math.Rounding.Ceil) + 2;
        } else {
            return Math.mulDiv(2 * C, 1e18, absB + sqrt, Math.Rounding.Ceil) + 2;
        }
    }

    function verifyEulerSwap(uint256 x, uint256 y, uint256 x0, uint256 y0, uint256 px, uint256 py, uint256 cx, uint256 cy) public view returns (bool) {        
        if (x > type(uint112).max || y > type(uint112).max) return false;
        if (x >= x0) {
            if (y >= y0) return true;
            return
                x >= fEulerSwap(y, py, px, y0, x0, cy);
        } else {
            if (y < y0) return false;            
            return
                y >= fEulerSwap(x, px, py, x0, y0, cx);
        }
    }

    function scaleUpX(uint256 x, uint256 x0) internal pure returns (uint256) {        
        return Math.mulDiv(x, x0, 1e18);
    }

    function scaleDownY(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {        
        return Math.mulDiv(py * 1e18, y - y0, x0 * px) + 1e18;
    }

    // function getScaledY(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
    //     uint256 p = px * 1e18 / py;
    //     uint256 scaledX = (x * 1e18) / x0;        
    //     return y0 + Math.mulDiv(p * x0, f(scaledX, c) - 1e18, 1e36);
    // }

    // function getScaledX(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
    //     uint256 p = px * 1e18 / py;
    //     uint256 scaledY = (y - y0) * 1e36 / (p * x0) + 1e18;        
    //     return quadratic(scaledY, c);
    // }

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
        console.log("B", B);
        uint256 absB = abs(B);
        console.log("absB", absB);
        uint256 squaredB = PRBMath.mulDiv(absB, absB, 1);        
        console.log("squaredB", squaredB);        
        uint256 discriminant = squaredB + Math.mulDiv(4 * c, (1e18 - c) * 1e18, 1e18);
        console.log("discriminant", discriminant);
        uint256 sqrt = Math.sqrt(discriminant);
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
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

    function test_Binary() public {
        uint256 cx = 0.1e18;
        uint256 y = 3.3243e18;
        uint256 startGas = gasleft();
        uint256 x = binary(y, cx, 1, 1e18);
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;
        uint256 yCalc = f(x, cx);
        console.log("y", y);
        console.log("yCalc", yCalc);
        console.log("x", x);
        console.log("delta", int256(y) - int256(yCalc));
        console.log("Gas used:", gasUsed);
        console.log();

        assert(y >= f(x, cx));
    }

    function test_Quadratic() public {
        uint256 cx = 1987860;
        uint256 y = 742411638020043034953197016458887439;
        uint256 yHalf = f(0.5e18, cx);
        uint256 startGas = gasleft();
        uint256 x = quadratic(y, cx);
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;
        uint256 yCalc = f(x, cx);
        uint256 xBin = x;
        console.log("y", y);
        console.log("yCalc", yCalc);
        console.log("x", x);
        console.log("delta", int256(y) - int256(yCalc));
        console.log("Gas used:", gasUsed);
        console.log();

        assertApproxEqAbs(x, xBin, 100);
    }

    function test_FuzzQuadraticBinary(uint256 y, uint256 cx) public {
        // Params
        cx = bound(cx, 1, 1e18);
        uint256 yMax = f(1, cx);
        y = bound(y, 1e18 + 1, yMax);
        uint256 startGas = gasleft();
        uint256 x = quadratic(y, cx);
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;
        uint256 yCalc = f(x, cx);
        console.log("y", y);
        console.log("yCalc", yCalc);
        console.log("x", x);
        console.log("delta", int256(y) - int256(yCalc));
        console.log("Gas used:", gasUsed);
        console.log();

        uint256 xBin = binary(y, cx, 1, 1e18);
        console.log("xBin", xBin);

        assert(y >= f(x, cx));        
    }

    // Test if we start with a y value, scale it down, solve for x, do we get back an x that passes invariant and is close to the original x
    function test_FuzzMappingMethod(uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy) public {
        // Params
        px = bound(px, 1e18, 1e32);
        py = bound(px, 1e18, 1e32);
        x0 = 1e26;
        y0 = 1e26;
        cx = bound(cx, 1, 1e18);
        cy = bound(cy, 1, 1e18);

        uint256 x = 30.214324e18;
        uint256 y = fEulerSwap(x, px, py, x0, y0, cx);
        console.log("x", x);
        console.log("y", y);

        uint256 yScaledDown = Math.mulDiv(y - y0, 1e36, Math.mulDiv(px, 1e18, py, Math.Rounding.Ceil) * x0, Math.Rounding.Floor) + 1e18;
        console.log("yScaledDown", yScaledDown);

        uint256 xScaledDownCalc = quadratic(yScaledDown, cx);
        console.log("xScaledDownCalc", xScaledDownCalc);

        uint256 xScaledUp = Math.mulDiv(xScaledDownCalc, x0, 1e18, Math.Rounding.Ceil);
        console.log("xScaledUp", xScaledUp);

        assert(verifyEulerSwap(xScaledUp, y, x0, y0, px, py, cx, cy));
        // assertApproxEqAbs(x, xScaledUp, 200);
    }

    // Test if we start with a y value, scale it down, solve for x, do we get back an x that passes invariant and is close to the original x
    function test_fInverse() public {
        // Params
        uint256 px = 24e18;
        uint256 py = 24e18;
        uint256 x0 = 1e26;
        uint256 y0 = 1e26;
        uint256 cx = 0.75e18;
        uint256 cy = 0.25e18;

        uint256 x = 30.214324e18;
        uint256 y = fEulerSwap(x, px, py, x0, y0, cx);
        uint256 startGas = gasleft();
        uint256 xCalc = fInverseEulerSwap(y, px, py, x0, y0, cx);
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;        
        uint256 yCalc = fEulerSwap(xCalc, px, py, x0, y0, cx);
        console.log("x", x);
        console.log("y", y);
        console.log("yCalc", yCalc);
        console.log("x", x);
        console.log("Gas used:", gasUsed);
    }

    function test_fuzzfInverse(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy) public {
        // Params
        x = bound(x, 0.05e18, 1e26 - 2); // TODO: note that the -2 here is the tolerance in the fInverse function. Without this, f() fails when x gets too close to centre.
        console.log("x", x);
        
        px = bound(px, 1e18, 1e32);
        py = bound(py, 1e18, 1e32);
        x0 = 1e26;
        y0 = bound(y0, 0, 1e26);
        cx = bound(cx, 1, 1e18);
        cy = bound(cy, 1, 1e18);

        uint256 y = fEulerSwap(x, px, py, x0, y0, cx);
        console.log("y", y);        
        uint256 xCalc = fInverseEulerSwap(y, px, py, x0, y0, cx);
        console.log("xCalc", xCalc);        
        uint256 yCalc = fEulerSwap(xCalc, px, py, x0, y0, cx);        
        console.log("yCalc", yCalc);

        if (x < type(uint112).max && y < type(uint112).max){
            assert(verifyEulerSwap(xCalc, y, x0, y0, px, py, cx, cy));
            assert(abs(int(y) - int(yCalc)) < 4 || abs(int(x) - int(xCalc)) < 4);
        }
    }    

    function test_fuzzfInverseScalingMethod(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy) public {
        // Params
        x = bound(x, 0.05e18, 1e26 - 2); // TODO: note that the -2 here is the tolerance in the fInverse function. Without this, f() fails when x gets too close to centre.
        console.log("x", x);
        
        px = bound(px, 1e18, 1e32);
        py = bound(py, 1e18, 1e32);
        x0 = 1e26;
        y0 = bound(y0, 0, 1e26);
        cx = bound(cx, 1, 1e18);
        cy = bound(cy, 1, 1e18);

        uint256 y = fEulerSwap(x, px, py, x0, y0, cx);
        console.log("y", y);
        uint256 yDown = scaleDownY(y, px, py, x0, y0, cx);
        console.log("yDown", yDown);
        uint256 xDownCalc = quadratic(y, cx);
        console.log("xDownCalc", xDownCalc);
        uint256 xCalc = scaleUpX(x, x0) / 1e8;
        console.log("xCalc", xCalc);
        console.log("xCheck", x == xCalc);
        uint256 yCalc = fEulerSwap(xCalc, px, py, x0, y0, cx);        
        console.log("yCalc", yCalc);

        if (x < type(uint112).max && y < type(uint112).max){
            assert(verifyEulerSwap(xCalc, y, x0, y0, px, py, cx, cy));
            assert(abs(int(y) - int(yCalc)) < 4 || abs(int(x) - int(xCalc)) < 4);
        }
    }    
}
