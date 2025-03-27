// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapScenarioTest is Test {
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

    function dfdx(uint256 x, uint256 c) internal pure returns (uint256) {
        return Math.mulDiv(1e18 - c, 1e36, x * x, Math.Rounding.Ceil) + c;
    }

    function newtons(uint256 y, uint256 c, uint256 xMin, uint256 xMax, uint256 yCalc) internal pure returns (uint256) {        
        uint256 x = xMax;
        for (uint256 i = 0; i < 10; i++) {
            int256 yDiff;
            if (i == 0) {
                // we already have a y-calculation to re-use on first iteration and know that x is not yet a lower bound
                yDiff = int256(yCalc) - int256(y);
            } else {
                yCalc = f(x, c);
                yDiff = int256(yCalc) - int256(y);
                if (yDiff == 0) {
                    return x;
                } else if (yDiff > 0) {
                    xMin = x; // only want x-calculations that are <= the true solution
                }
            }
            int256 xN = int256(x) + (yDiff * (1e18 - 1) / 1e18) / int256(dfdx(x, c));
            if (xN == int256(x)) {
                return xMin;
            } else if (xN < int256(xMin)) {
                x = xMin;
            } else if (xN >= int256(xMin) && xN <= 1e18) {                
                x = uint256(xN);
            }
            console.log();
        }
        console.log();
    }

    function secant(uint256 y, uint256 c, uint256 xMin, uint256 xMax, uint256 yCalc) internal pure returns (uint256) {
        return xMin + uint256((int256(yCalc) - int256(y)) * int256(xMax - xMin) / (int256(yCalc) - int256(f(xMax, c))));
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function quadratic(uint256 y, uint256 c) internal pure returns (uint256) {
        int256 B = int256(y) - 2 * int256(c);        
        uint256 discriminant = uint256(B * B) + 4 * (1e18 - c) * c;
        uint256 sqrt = Math.sqrt(discriminant);
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;        
        if (B < 0) {
            return Math.mulDiv(2 * c - y + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 1; 
        } else {
            return Math.mulDiv(2 * (1e18 - c), 1e18, uint256(B) + sqrt, Math.Rounding.Ceil) + 1; 
        }        
    }

    // Note: second if statement fixes off-by-one error
    // if xMin == xMax - 1 and and y >= f(xMin, c) is true, then xMid = (xMin + xMax) / 2 = xMin and xMax = xMid = xMin, but we never tested xMax
    function binary(uint256 y, uint256 c, uint256 xMin, uint256 xMax) internal pure returns (uint256) {
        uint256 count = 0;
        if(xMin < 1) {
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

    function fInverse(uint256 y, uint256 c) internal pure returns (uint256) {
        uint256 x = quadratic(y, c); // get an initial x
        uint256 yCalc = f(x, c); // calculate the y given the x
        if (y == yCalc) {
            return x; // quadratic worked exactly
        } else {
            uint256 xMin = (1e18 - c) * 1e18 / y; // get an initial lower bound
            xMin = xMin < 1 ? 1 : xMin;
            uint256 xMax = 1e18;

            if (y > yCalc) {
                console.log("newtwons");
                xMax = x; // quadratic slightly over-estimated x, so use as upper bound
                xMin = newtons(y, c, xMin, xMax, yCalc); // get a nearby lower bound using Newton's method
            } else {
                console.log("secant");
                xMin = x; // quadratic slightly under-estimated x, so use as lower bound
                xMax = secant(y, c, xMin, xMax, yCalc); // get a nearby upper bound using secant method
            }

            return binary(y, c, xMin, xMax); // refine the bounds using binary search
        }
    }

    function test_Binary() public {
        uint256 cx = 0.1e18;
        uint256 cy = 0.5e18;
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
        uint256 cy = 0.5e18;
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
        uint256 cy = 0.5e18;

        uint256 yMax = f(1, cx);        
        y = bound(y, 1e18 + 1, yMax);
        uint256 startGas = gasleft();
        uint256 x = quadratic(y, cx);
        x = binary(y, cx, x - 2, x);
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
        assertApproxEqAbs(x, xBin, 1);        
    }

}
