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

    function fInverse(uint256 y, uint256 c, uint256 guess) public pure returns (uint256) {
        uint256 x = guess;
        for (uint256 i = 0; i < 50; i++) {
            // f(x): cx * x^2 + (y - 2cx) * x - (1 - cx)
            // round down if we want to give overall over-estimate
            uint256 x2Higher = x * x;
            int256 fxHigher =
                int256(c * x2Higher / 1e18) + ((int256(y) - 2 * int256(c)) * int256(x)) - int256(1e18 - c) * 1e18;

            // f'(x): 2cx * x + (y - 2cx)
            // round up if we want to give overall over-estimate
            int256 fpxHigher = int256(2 * c * x) + (int256(y) - 2 * int256(c)) * 1e18;

            // Newton step: x = x - f(x)/f'(x)
            int256 xnHigher = int256(x) - (fxHigher * 1e18) / fpxHigher;
            if (int256(x) - xnHigher < 1) break; // Stop if change is too small
            x = uint256(xnHigher);
        }
        return x;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function fInverseSqrt(uint256 y, uint256 c) public pure returns (uint256) {
        uint256 A = c;
        int256 B = int256(y) - int256(2 * c);
        int256 C = -int256(1e18 - c);

        uint256 discriminant = uint256(B * B - 4 * int256(A) * C) * 1e18;
        uint256 sqrt = Math.sqrt(discriminant) / 1e9;
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;
        uint256 numerator = uint256(int256(sqrt) - B);
        uint256 x = Math.mulDiv(numerator, 1e18, 2 * A);

        return fInverse(y, c, x) + 1;
    }

    function getY(uint256 x, uint256 p, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        uint256 scaledX = (x * 1e18) / x0;
        return y0 + Math.mulDiv(p * x0, f(scaledX, c) - 1e18, 1e36);
    }

    function getX(uint256 y, uint256 p, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        uint256 scaledY = (y - y0) * 1e36 / (p * x0) + 1e18;
        return fInverse(scaledY, c, 1e18 + 1);
    }

    // function test_fuzzF(uint256 x, uint256 cx) public {
    //     // Params
    //     cx = bound(cx, 2, 1e18);
    //     console.log("cx", cx);

    //     x = bound(x, 0.05e18, 1e18 - 1);
    //     console.log("x", x);

    //     uint256 y = f(x, cx);
    //     console.log("y", y);
    // }

    function test_FInverseSmallXValues() public {
        // Params
        uint256 cx = 999999999999999999;
        console.log("cx", cx);

        uint256 smallestX = 2;
        console.log("smallestX", smallestX);
        uint256 largestY = f(smallestX, cx);
        console.log("largestY", largestY);
        console.log();

        uint256 startGas = gasleft();
        uint256 smallestXCalc = fInverse(largestY, cx, 1e18 + 1);
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;
        console.log("smallestXCalc", smallestX);
        console.log();
        console.log("Gas used:", gasUsed);
        console.log();

        startGas = gasleft();
        uint256 smallestXSqrtCalc = fInverseSqrt(largestY, cx);
        endGas = gasleft();
        gasUsed = startGas - endGas;
        console.log("smallestXSqrtCalc", smallestXSqrtCalc);
        console.log();
        console.log("Gas used:", gasUsed);
        console.log();
    }

    function test_FInverseLargeXValues() public {
        // Params
        uint256 cx = 1;
        console.log("cx", cx);

        uint256 largestX = 1e18;
        console.log("smallestX", largestX);
        uint256 smallestY = f(largestX, cx);
        console.log("largestY", smallestY);
        console.log();

        uint256 startGas = gasleft();
        uint256 largestXCalc = fInverse(smallestY, cx, 1e18 + 1);
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;
        console.log("largestXCalc", largestXCalc);
        console.log();
        console.log("Gas used:", gasUsed);
        console.log();

        startGas = gasleft();
        uint256 largestXSqrtCalc = fInverseSqrt(smallestY, cx);
        endGas = gasleft();
        gasUsed = startGas - endGas;
        console.log("largestXSqrtCalc", largestXSqrtCalc);
        console.log();
        console.log("Gas used:", gasUsed);
        console.log();
    }

    // function test_FInverse() public {
    //     // Params
    //     uint256 cx = 228420421061113445;
    //     console.log("cx", cx);

    //     uint256 y = 195511056398330993093780238671459770;
    //     console.log("y", y);
    //     console.log();

    //     uint256 startGas = gasleft();
    //     uint256 x = fInverse(y, cx);
    //     uint256 endGas = gasleft();
    //     uint256 gasUsed = startGas - endGas;
    //     console.log("x", x);

    //     console.log();
    //     console.log("Gas used:", gasUsed);
    //     console.log();

    //     startGas = gasleft();
    //     uint256 xSqrt = fInverseSqrt(y, cx);
    //     endGas = gasleft();
    //     gasUsed = startGas - endGas;
    //     console.log("xSqrt", xSqrt);

    //     console.log();
    //     console.log("Gas used:", gasUsed);
    //     console.log();

    //     if (x > 2) {
    //         uint256 yCalcBelow2 = f(x - 2, cx);
    //         console.log("xBelow2", x - 2);
    //         console.log("yCalcBelow2", yCalcBelow2);
    //         console.log("diff", int256(y) - int256(yCalcBelow2));
    //         console.log();
    //     }

    //     uint256 yCalcBelow = f(x - 1, cx);
    //     console.log("xBelow", x - 1);
    //     console.log("yCalcBelow", yCalcBelow);
    //     console.log("diff", int256(y) - int256(yCalcBelow));
    //     console.log();

    //     uint256 yCalc = f(x, cx);
    //     console.log("x", x);
    //     console.log("yCalc", yCalc);
    //     console.log("diff", int256(y) - int256(yCalc));
    //     console.log();

    //     uint256 ySqrtCalc = f(xSqrt, cx);
    //     console.log("xSqrt", xSqrt);
    //     console.log("ySqrtCalc", ySqrtCalc);
    //     console.log("diff", int256(y) - int256(ySqrtCalc));
    //     console.log();

    //     uint256 yCalcAbove = f(x + 1, cx);
    //     console.log("xAbove", x + 1);
    //     console.log("yCalcAbove", yCalcAbove);
    //     console.log("diff", int256(y) - int256(yCalcAbove));
    // }

    function test_fuzzFInverse(uint256 y, uint256 cx) public {
        // Params
        cx = bound(cx, 1, 1e18);
        uint256 cy = cx;
        console.log("cx", cx);

        // restrict trading to 90% of X liquidity
        uint256 smallestX = 0.1e18;
        console.log("smallestX", smallestX);
        uint256 largestY = f(smallestX, cx);
        console.log("largestY", largestY);

        y = bound(y, 1e18 + 1, largestY);
        console.log("y", y);
        console.log();

        uint256 startGas = gasleft();
        uint256 x = fInverse(y, cx, 1e18 + 1);
        uint256 endGas = gasleft();
        uint256 gasUsed = startGas - endGas;

        console.log("x", x);
        console.log("Gas used:", gasUsed);
        console.log();

        startGas = gasleft();
        uint256 xSqrt = fInverseSqrt(y, cx);
        endGas = gasleft();
        gasUsed = startGas - endGas;
        console.log("xSqrt", xSqrt);
        console.log("Gas used:", gasUsed);
        console.log();

        // if (x > 2) {
        //     uint256 yCalcBelow2 = f(x - 2, cx);
        //     console.log("xBelow2", x - 2);
        //     console.log("yCalcBelow2", yCalcBelow2);
        //     console.log("diff", int256(y) - int256(yCalcBelow2));
        //     console.log();
        // }

        // uint256 yCalcBelow = f(x - 1, cx);
        // console.log("xBelow", x - 1);
        // console.log("yCalcBelow", yCalcBelow);
        // console.log("diff", int256(y) - int256(yCalcBelow));
        // console.log();

        uint256 yCalc = f(x, cx);
        console.log("x", x);
        console.log("yCalc", yCalc);
        console.log("diff", int256(y) - int256(yCalc));
        console.log(verify(x, y, cx, cy));
        console.log();

        uint256 ySqrtCalc = f(xSqrt, cx);
        console.log("xSqrt", xSqrt);
        console.log("ySqrtCalc", ySqrtCalc);
        console.log("diff", int256(y) - int256(ySqrtCalc));
        console.log(verify(xSqrt, y, cx, cy));
        console.log();

        // uint256 yCalcAbove = f(x + 1, cx);
        // console.log("xAbove", x + 1);
        // console.log("yCalcAbove", yCalcAbove);
        // console.log("diff", int256(y) - int256(yCalcAbove));

        assert(verify(xSqrt, y, cx, cy));
        // assert();

        // assertGe(int256(y) - int256(ySqrtCalc), 0);
        // assertGe(int256(y) - int256(yCalc), 0);
        // assertLt(int256(y) - int256(yCalcBelow), 0);
        // assertApproxEqAbs(y, yCalc, 1e3);
        // assertApproxEqAbs(y, ySqrtCalc, 1e3);
    }
}
