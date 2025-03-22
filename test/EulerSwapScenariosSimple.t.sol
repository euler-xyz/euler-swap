// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapScenarioTest is Test {
    
    function verify(
        uint256 newReserve0,
        uint256 newReserve1,
        uint256 px,
        uint256 py,
        uint256 x0,
        uint256 y0,
        uint256 cx,
        uint256 cy
    ) public view returns (bool) {
        if (newReserve0 > type(uint112).max || newReserve1 > type(uint112).max) return false;

        if (newReserve0 >= x0) {
            if (newReserve1 >= y0) return true;
            return newReserve0 >= g(newReserve0, px, py, x0, y0, cy);
        } else {
            if (newReserve1 < y0) return false;
            return newReserve1 >= f(newReserve0, px, py, x0, y0, cx);
        }
    }

    function getB(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (int256)
    {
        uint256 term1 = Math.mulDiv(py, (y - y0 - 1), px, Math.Rounding.Ceil);
        int256 term2 = (2 * int256(c) - 1e18) * int256(x0) / 1e18;
        return int256(term1) - term2;
    }

    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            // console.log("v", v);
            require(v <= type(uint248).max, "Help!");
            // console.log("y0 + (v + (py - 1)) / py", y0 + (v + (py - 1)) / py);
            return y0 + (v + (py - 1)) / py;
        }
    }
    
    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c, uint256 xMin)
        internal
        pure
        returns (uint256)
    {
        int256 B = int256(py * (y - y0) / px) + int256(x0) * (int256(1e18) - 2 * int256(c)) / 1e18;
        console.log("B", B);

        // B^2 component, using FullMath for overflow safety
        uint256 absB = B < 0 ? uint256(-B) : uint256(B);
        console.log("absB", absB);
        uint256 squaredB = Math.mulDiv(absB, absB, 1e18, Math.Rounding.Ceil);
        // uint256 squaredB = Math.mulDiv(absB / 1e18 + 1, absB, 1, Math.Rounding.Ceil) * 1e36;
        console.log("squaredB", squaredB);
        // console.log("squaredB", squaredB);

        // 4 * A * C component of the quadratic formula
        uint256 AC4 = Math.mulDiv(
            Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil),
            Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil),
            1e18,
            Math.Rounding.Ceil
        );

        console.log("4AC", AC4);
        console.log("A / B", c * 1e18 / absB);
        console.log("C / B", (1e18 - c) * x0 * x0 / absB);

        // Discriminant: b^2 + 4ac, scaled up to maintain precision
        uint256 discriminant = (squaredB + AC4) * 1e18;

        // Square root of the discriminant (rounded up)
        uint256 sqrt = Math.sqrt(discriminant);
        sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt;

        // Compute and return x = fInverse(y) using the quadratic formula
        return Math.mulDiv(uint256(int256(sqrt) - B), 1e18, 2 * c, Math.Rounding.Ceil);
    }

        function g(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        return f(y, py, px, y0, x0, c);
    }


    function gInverse(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c, uint256 xMin)
        internal
        pure
        returns (uint256)
    {
        return fInverse(x, py, px, y0, x0, c, xMin);
    }

    function test_F() public view {
        // Params
        uint256 x0 = 40506059417043057209;
        uint256 y0 = 50000000000000000000;
        uint256 px = 1000000000000000000;
        uint256 py = 43067456379334984;
        uint256 cx = 800290974685695047;
        uint256 cy = 911725765025283277;

        console.log("x0", x0);
        console.log("y0", y0);
        console.log("px", px);
        console.log("py", py);
        console.log("cx", cx);
        console.log("cy", cy);

        (uint256 xMin, uint256 yMax) = getMinXMaxY(px, py, x0, y0, cx);

        console.log("xMin", xMin);
        console.log("yMax", yMax);

        uint256 x = 36717501059877983599 + 1;
        console.log("x", x);
        uint256 y = f(x, px, py, x0, y0, cx);
        console.log("y", y);
        // uint256 x = fInverse(y, px, py, x0, y0, cx);
        // console.log("x", x);
        // uint256 yCalc = f(x, px, py, x0, y0, cx);
        // console.log("yCalc", yCalc, y);

        // Check the calculated variables pass the invariant
        if (x <= type(uint112).max && y <= type(uint112).max) {
            console.log("In range (x, y)");
            assert(verify(x, y, px, py, x0, y0, cx, cy));
        }

        // // Check the re-calculated variables pass the invariant
        // if (x <= type(uint112).max && yCalc <= type(uint112).max) {
        //     console.log("In range (x, yCalc)");
        //     assert(verify(x, yCalc, px, py, x0, y0, cx, cy));
        // }
    }
}
