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

    function quadratic(uint256 x, uint256 c, int256 B, int256 C) internal pure returns (int256) {
        uint256 xSquared = Math.mulDiv(x, x, 1e18, Math.Rounding.Ceil); // Ensure rounding up
        int256 term1 = int256(Math.mulDiv(c, xSquared, 1e18, Math.Rounding.Ceil)); // c * x^2 / 1e18 (rounded up)
        int256 term2 = (B * int256(x) + (1e18 - 1)) / 1e18; // Equivalent to (B * x / 1e18) rounding up
        return term1 + term2 + C;
    }

    function quadraticDerivative(uint256 x, uint256 c, int256 B) internal pure returns (int256) {
        return int256(Math.mulDiv(2 * c, x, 1e18)) + B;
    }

    function quadraticInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c, uint256 xMin)
        public
        pure
        returns (uint256)
    {
        if (y == y0) {
            return x0;
        }
        uint256 xN = x0 / 2;

        uint256 A = c;
        console.log("A", A);
        int256 B = getB(y, px, py, x0, y0, c);
        console.log("B", B);
        int256 C = -((int256(1e18) - int256(c)) * int256(Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil))) / 1e18;
        console.log("C", C);
        console.log();
        console.log("y", y);

        for (uint256 i = 0; i < 10; i++) {
            // console.log("xN:", xN);
            // console.log("yN:", f(xN, px, py, x0, y0, c));
            // console.log();
            int256 xNPlus1 = int256(xN) - (quadratic(xN, A, B, C) * 1e18) / quadraticDerivative(xN, A, B); // Scaled division for precision
            if (xNPlus1 < int256(xMin)) {
                xNPlus1 = int256(xMin);
            } else if (xNPlus1 > int256(x0) - 1) {
                xNPlus1 = int256(x0) - 1;
            }
            if (abs(int256(xN) - xNPlus1) < 1) break; // Stop if change is too small
            xN = uint256(xNPlus1);
        }
        return xN;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            console.log("v", v);
            require(v <= type(uint248).max, "Help!");
            console.log("y0 + (v + (py - 1)) / py", y0 + (v + (py - 1)) / py);
            return y0 + (v + (py - 1)) / py;
        }
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
        // return quadraticInverse(x, py, px, y0, x0, c);
    }

    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c, uint256 xMin)
        internal
        pure
        returns (uint256)
    {
        return quadraticInverse(y, px, py, x0, y0, c, xMin);
    }

    function getMinXMaxY(uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 xMin = 1;
        uint256 xMax = x0 - 1;
        // binary search for the smallest valid X value
        // smallest valid X corresponds to the maximum valid Y, given numerical limits
        while (xMin < xMax) {
            uint256 xMid = xMin + (xMax - xMin) / 2;
            uint256 yMid = f(xMid, px, py, x0, y0, c);
            if (yMid < type(uint112).max) {
                xMax = xMid;
            } else {
                xMin = xMid + 1;
            }
        }
        uint256 yMax = f(xMin, px, py, x0, y0, c);
        console.log(xMin, yMax, yMax < type(uint112).max);
        return (xMin, yMax);
    }

    function fInverse2(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c, uint256 xMin)
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

    // function test_FInverse() public view {
    //     // Params
    //     uint256 x0 = 50e18;
    //     uint256 y0 = 50e18;
    //     uint256 px = 1e36;
    //     uint256 py = 1;
    //     uint256 cx = 0.999e18;
    //     uint256 cy = 0.001e18;

    //     console.log("x0", x0);
    //     console.log("y0", y0);
    //     console.log("px", px);
    //     console.log("py", py);
    //     console.log("cx", cx);
    //     console.log("cy", cy);

    //     (uint256 xMin, uint256 yMax) = getMinXMaxY(px, py, x0, y0, cx);

    //     console.log("xMin", xMin);
    //     console.log("yMax", yMax);

    //     uint256 y = f(xMin, px, py, x0, y0, cx);
    //     console.log("y", y);
    //     uint256 x = fInverse(y, px, py, x0, y0, cx);
    //     console.log("x", x);
    //     uint256 yCalc = f(x, px, py, x0, y0, cx);
    //     console.log("yCalc", yCalc, y);

    //     // Check the calculated variables pass the invariant
    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         console.log("In range (x, y)");
    //         assert(verify(x, y, px, py, x0, y0, cx, cy));
    //     }

    //     // Check the re-calculated variables pass the invariant
    //     if (x <= type(uint112).max && yCalc <= type(uint112).max) {
    //         console.log("In range (x, yCalc)");
    //         assert(verify(x, yCalc, px, py, x0, y0, cx, cy));
    //     }
    // }

    // function test_fuzzF(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy) public view {
    //     // Params
    //     x0 = 50e18;
    //     y0 = bound(y0, 0, 50e18);
    //     px = 1e18;
    //     py = bound(py, 1, 1e36);
    //     cx = bound(cx, 1, 1e18);
    //     cy = bound(cy, 1, 1e18);

    //     console.log("x0", x0);
    //     console.log("y0", y0);
    //     console.log("px", px);
    //     console.log("py", py);
    //     console.log("cx", cx);
    //     console.log("cy", cy);

    //     x = bound(x, 0.1e18, x0 - 1);
    //     console.log("x", x);
    //     uint256 y = f(x, px, py, x0, y0, cx);
    //     console.log("y", y);
    //     uint256 xCalc = fInverse(y, px, py, x0, y0, cx);
    //     console.log("xCalc", xCalc);

    //     // Check the calculated variables pass the invariant
    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         console.log("In range (x, y)");
    //         assert(verify(x, y, px, py, x0, y0, cx, cy));
    //     }

    //     // Check the re-calculated variables pass the invariant
    //     if (xCalc <= type(uint112).max && y <= type(uint112).max) {
    //         console.log("In range (x, yCalc)");
    //         assert(verify(x, y, px, py, x0, y0, cx, cy));
    //     }
    // }

    function test_fuzzFInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx, uint256 cy)
        public
        view
    {
        // Params
        x0 = bound(x0, 1e3, 1e28);
        y0 = bound(x0, 0, 1e28);
        px = 1e18;
        py = bound(py, 1, 1e28);
        cx = bound(cx, 1, 1e18);
        cy = bound(cy, 1, 1e18);

        console.log("x0", x0);
        console.log("y0", y0);
        console.log("px", px);
        console.log("py", py);
        console.log("cx", cx);
        console.log("cy", cy);

        (uint256 xMin, uint256 yMax) = getMinXMaxY(px, py, x0, y0, cx);

        console.log("xMin", xMin);
        console.log("yMax", yMax);

        y = bound(y, y0 + 1, y0 + 1 + 4 * y0);
        console.log("y", y);
        uint256 x = fInverse2(y, px, py, x0, y0, cx, xMin);
        console.log("x", x);

        // uint256 yCalc = f(x, px, py, x0, y0, cx);
        // console.log("yCalc", yCalc, y, yCalc - y);        

        // console.log("x - 1", x + 1);
        // uint256 yCalc2 = f(x + 1, px, py, x0, y0, cx);

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

    // function test_fuzzG(uint256 y) public view {
    //     y = bound(y, 1, y0 - 1);
    //     uint256 x = g(y, px, py, x0, y0, cy);
    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         assert(verify(x, y));
    //     }
    // }

    // function test_fuzzGInverse(uint256 x) public view {
    //     x = bound(x, x0 + 2, type(uint112).max - x0 - 1);
    //     uint256 y = gInverse(x, px, py, x0, y0, cy);
    //     uint256 xCalc = g(y, px, py, x0, y0, cy);

    //     console.log(x, y, xCalc);

    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         assert(verify(x, y));
    //     }
    // }

    // function test_fuzzFInvariantDomain2(uint256 x) public view {
    //     x = bound(x, x0 + 1, type(uint112).max);
    //     uint256 y = gInverse(x, px, py, x0, y0, cy);
    //     console.log(x, y);

    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         assert(verify(x, y));
    //     }
    // }

    // function test_fuzzFInverseInvariantDomain2(uint256 y) public view {
    //     y = bound(y, 1, y0 - 1);
    //     uint256 x = g(y, px, py, x0, y0, cy);
    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         assert(verify(x, y));
    //     }
    // }

    // function test_fuzzScenario1A(uint256 xIn) public view {
    //     // ### 1a. Swap `xIn` and remain in domain 1
    //     // **Calculation steps:**
    //     // 1. `xNew = x + xIn`
    //     // 2. `yNew = f(xNew)`
    //     // **Invariant check:**
    //     // `yNew >= f(xNew) = f(x + xIn)`
    //     xIn = bound(xIn, 0, x0 - 2);
    //     uint256 x = 1;
    //     uint256 xNew = x + xIn;
    //     uint256 yNew = f(xNew, px, py, x0, y0, cx);
    //     // domain check
    //     assertLe(xNew, x0);
    //     assertGe(yNew, y0);
    //     // direct invariant check
    //     assertGe(yNew, f(xNew, px, py, x0, y0, cx));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario1B(uint256 xIn) public view {
    //     // ### 1b. Swap `xIn` and move to domain 2
    //     // **Calculation steps:**
    //     // 1. `xNew = x + xIn`
    //     // 2. `yNew = gInverse(xNew)`
    //     // **Invariant check:**
    //     // `xNew >= g(yNew) = g(gInverse(xNew)) = g(gInverse(x + xIn))`
    //     xIn = bound(xIn, x0, type(uint112).max);
    //     uint256 x = 1;
    //     uint256 xNew = x + xIn;
    //     uint256 yNew = gInverse(xNew, px, py, x0, y0, cy);
    //     // domain check
    //     assertGe(xNew, x0);
    //     assertLe(yNew, y0);
    //     // direct invariant check
    //     assertGe(xNew, g(yNew, px, py, x0, y0, cy));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario2(uint256 yIn) public view {
    //     // ### 2. Swap `yIn` and remain in domain 1
    //     // **Calculation steps:**
    //     // 1. `yNew = y + yIn`
    //     // 2. `xNew = fInverse(yNew)`
    //     // **Invariant check:**
    //     // `yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y + yIn))`
    //     yIn = bound(yIn, 0, type(uint112).max);
    //     uint256 y = y0 + 1;
    //     uint256 yNew = y + yIn;
    //     uint256 xNew = fInverse(yNew, px, py, x0, y0, cx);
    //     // domain check
    //     assertLe(xNew, x0);
    //     assertGe(yNew, y0);
    //     // direct invariant check
    //     assertGe(yNew, f(xNew, px, py, x0, y0, cx));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario3(uint256 xOut) public view {
    //     // ### 3. Swap `xOut` and remain in domain 1
    //     // **Calculation steps:**
    //     // 1. `xNew = x - xOut`
    //     // 2. `yNew = f(xNew)`
    //     // **Invariant check:**
    //     // `yNew >= f(xNew) = f(x - xOut)`
    //     xOut = bound(xOut, 0, x0 - 2);
    //     uint256 x = x0 - 1;
    //     uint256 xNew = x - xOut;
    //     uint256 yNew = f(xNew, px, py, x0, y0, cx);
    //     // domain check
    //     assertLe(xNew, x0);
    //     assertGe(yNew, y0);
    //     // direct invariant check
    //     assertGe(yNew, f(xNew, px, py, x0, y0, cx));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario4A(uint256 yOut) public view {
    //     // ### 4a. Swap `yOut` and remain in domain 1
    //     // **Calculation steps:**
    //     // 1. `yNew = y - yOut`
    //     // 2. `xNew = fInverse(yNew)`
    //     // **Invariant check:**
    //     // `yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y - yOut))`
    //     yOut = bound(yOut, 0, type(uint112).max - (y0 + 1));
    //     uint256 y = type(uint112).max;
    //     uint256 yNew = y - yOut;
    //     uint256 xNew = fInverse(yNew, px, py, x0, y0, cx);
    //     // domain check
    //     assertLe(xNew, x0);
    //     assertGe(yNew, y0);
    //     // direct invariant check
    //     assertGe(yNew, f(xNew, px, py, x0, y0, cx));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario4B(uint256 yOut) public view {
    //     // ### 4b. Swap `yOut` and move to domain 2
    //     // **Calculation steps:**
    //     // 1. `yNew = y - yOut`
    //     // 2. `xNew = g(yNew)`
    //     // **Invariant check:**
    //     // `xNew >= g(yNew) = g(y - yOut)`
    //     yOut = bound(yOut, 1, y0 - 1);
    //     uint256 y = y0;
    //     uint256 yNew = y - yOut;
    //     uint256 xNew = g(yNew, px, py, x0, y0, cy);
    //     // domain check
    //     assertGe(xNew, x0);
    //     assertLe(yNew, y0);
    //     // direct invariant check
    //     assertGe(xNew, g(yNew, px, py, x0, y0, cy));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario5(uint256 xIn) public view {
    //     // ### 5. Swap `xIn` and remain in domain 2
    //     // **Calculation steps:**
    //     // 1. `xNew = x + xIn`
    //     // 2. `yNew = gInverse(xNew)`
    //     // **Invariant check:**
    //     // `xNew >= g(yNew) = g(gInverse(xNew)) = g(gInverse(x + xIn))`
    //     xIn = bound(xIn, 0, type(uint112).max - 1);
    //     uint256 x = x0 + 1;
    //     uint256 xNew = x + xIn;
    //     uint256 yNew = gInverse(xNew, px, py, x0, y0, cy);
    //     // domain check
    //     assertGe(xNew, x0);
    //     assertLe(yNew, y0);
    //     // direct invariant check
    //     assertGe(xNew, g(yNew, px, py, x0, y0, cy));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario6a(uint256 yIn) public view {
    //     // ### 6a. Swap `yIn` and remain in domain 2
    //     // **Calculation steps:**
    //     // 1. `yNew = y + yIn`
    //     // 2. `xNew = g(yNew)`
    //     // **Invariant check:**
    //     // `xNew >= g(yNew) = g(y + yIn)`
    //     yIn = bound(yIn, 0, y0 - 2);
    //     uint256 y = 1;
    //     uint256 yNew = y + yIn;
    //     uint256 xNew = g(yNew, px, py, x0, y0, cy);
    //     // domain check
    //     assertGe(xNew, x0);
    //     assertLe(yNew, y0);
    //     // direct invariant check
    //     assertGe(xNew, g(yNew, px, py, x0, y0, cy));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario6b(uint256 yIn) public view {
    //     // ### 6b. Swap `yIn` and move to domain 1
    //     // **Calculation steps:**
    //     // 1. `yNew = y + yIn`
    //     // 2. `xNew = fInverse(yNew)`
    //     // **Invariant check:**
    //     // `yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y + yIn))`
    //     yIn = bound(yIn, 1, type(uint112).max);
    //     uint256 y = y0;
    //     uint256 yNew = y + yIn;
    //     uint256 xNew = fInverse(yNew, px, py, x0, y0, cx);
    //     // domain check
    //     assertLe(xNew, x0);
    //     assertGe(yNew, y0);
    //     // direct invariant check
    //     assertGe(yNew, f(xNew, px, py, x0, y0, cx));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario7a(uint256 xOut) public view {
    //     // ### 7a. Swap `xOut` and remain in domain 2
    //     // **Calculation steps:**
    //     // 1. `xNew = x - xOut`
    //     // 2. `yNew = gInverse(xNew)`
    //     // **Invariant check:**
    //     // `xNew >= g(xNew) = g(x - xOut)`
    //     xOut = bound(xOut, 0, type(uint112).max - x0 - 1);
    //     uint256 x = type(uint112).max;
    //     uint256 xNew = x - xOut;
    //     uint256 yNew = gInverse(xNew, px, py, x0, y0, cy);
    //     // domain check
    //     assertGe(xNew, x0);
    //     assertLe(yNew, y0);
    //     // direct invariant check
    //     assertGe(xNew, g(yNew, px, py, x0, y0, cy));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario7b(uint256 xOut) public view {
    //     // ### 7b. Swap `xOut` and move to domain 1
    //     // **Calculation steps:**
    //     // 1. `xNew = x - xOut`
    //     // 2. `yNew = f(xNew)`
    //     // **Invariant check:**
    //     // `yNew >= f(xNew) = f(x - xOut)`
    //     xOut = bound(xOut, 0, x0 - 2);
    //     uint256 x = x0 - 1;
    //     uint256 xNew = x - xOut;
    //     uint256 yNew = f(xNew, px, py, x0, y0, cx);
    //     // domain check
    //     assertLe(xNew, x0);
    //     assertGe(yNew, y0);
    //     // direct invariant check
    //     assertGe(yNew, f(xNew, px, py, x0, y0, cx));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }

    // function test_fuzzScenario8(uint256 yOut) public view {
    //     // ### 8. Swap `yOut` and remain in domain 2
    //     // **Calculation steps:**
    //     // 1. `yNew = y - yOut`
    //     // 2. `xNew = g(yNew)`
    //     // **Invariant check:**
    //     // `xNew >= g(yNew) = g(y - yOut)`
    //     yOut = bound(yOut, 0, y0 - 2);
    //     uint256 y = y0 - 1;
    //     uint256 yNew = y - yOut;
    //     uint256 xNew = g(yNew, px, py, x0, y0, cy);
    //     // domain check
    //     assertGe(xNew, x0);
    //     assertLe(yNew, y0);
    //     // direct invariant check
    //     assertGe(xNew, g(yNew, px, py, x0, y0, cy));
    //     // main ivariant check
    //     if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
    //         assert(verify(xNew, yNew));
    //     }
    // }
}
