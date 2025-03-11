// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapScenarioTest is Test {
    // Global params
    uint256 x0 = 200.323e18;
    uint256 y0 = 100e18;
    uint256 px = 1e18;
    uint256 py = 1.3432e18;
    uint256 cx = 0.91243e18;
    uint256 cy = 0.1e18;

    function verify(uint256 x, uint256 y) public view returns (bool) {
        if (x > type(uint112).max || y > type(uint112).max) return false;

        if (x >= x0) {
            if (y >= y0) return true;
            return x >= g(y, px, py, x0, y0, cy);
        } else {
            if (y < y0) return false;
            return y >= f(x, px, px, x0, y0, cx);
        }
    }

    function getB(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (int256)
    {
        uint256 term1 = py * (y - y0) / px;
        int256 term2 = (2 * int256(c) - 1e18) * int256(x0) / 1e18;
        console.log("t1", term1);
        console.log("t2", term2);
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

    function quadraticInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        public
        pure
        returns (uint256)
    {
        uint256 linearApprox = py * (y - y0) / px;
        uint256 xN;
        if(linearApprox > x0) {
            xN = x0 * 1e18 / 2e18;
        } else {
            xN = x0 - linearApprox;            
        }
        
        uint256 A = c;
        int256 B = getB(y, px, py, x0, y0, c);
        int256 C = -((int256(1e18) - int256(c)) * int256(Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil))) / 1e18;

        for (uint256 i = 0; i < 10; i++) {
            console.log("xN:", xN);
            int256 xNPlus1 = int256(xN) - (quadratic(xN, A, B, C) * 1e18) / quadraticDerivative(xN, A, B); // Scaled division for precision
            if (abs(int256(xN) - xNPlus1) < 1) break; // Stop if change is too small
            if (xNPlus1 < 0) {
                xNPlus1 = 1;
            }
            xN = uint256(xNPlus1);
        }
        return xN;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
        return y0 + (v + (py - 1)) / py;
    }

    function g(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        return f(y, py, px, y0, x0, c);
    }

    function gInverse(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        return fInverse(x, py, px, y0, x0, c);
    }

    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        // A component of the quadratic formula: a = 2 * c
        uint256 A = 2 * c;

        // B component of the quadratic formula
        int256 B = int256((px * (y - y0) + py - 1) / py) - int256((x0 * (2 * c - 1e18) + 1e18 - 1) / 1e18);

        // B^2 component, using FullMath for overflow safety
        uint256 absB = B < 0 ? uint256(-B) : uint256(B);
        uint256 squaredB = Math.mulDiv(absB, absB, 1e18) + (absB * absB % 1e18 == 0 ? 0 : 1);

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

    function test_numericInverseDomain1() public view {
        uint256 xInit = 20e18;
        uint256 y = f(xInit, px, py, x0, y0, cx);
        // console.log("xInit:", xInit);
        // console.log("y:", y);
        // uint256 gasStart = gasleft();
        // uint256 x = quadraticInverse(y, px, py, x0, y0, cx);
        // uint256 gasUsed = gasStart - gasleft();
        // console.log("Gas used Newton:", gasUsed);
        // console.log("x:", x);

        // gasStart = gasleft();
        // uint256 xExact = fInverse(y, px, py, x0, y0, cx);
        // gasUsed = gasStart - gasleft();
        // console.log("Gas used exact:", gasUsed);
        // console.log("xExact:", xExact);

        if (x <= type(uint112).max && y <= type(uint112).max) {
            console.log("In range (x, y), so running verify");
            assert(verify(xInit, y));
        }
    }

    // function test_numericInverseDomain2() public view {
    //     uint256 yInit = 1e18;
    //     uint256 x = g(yInit, px, py, x0, y0, cy);
    //     console.log("yInit:", yInit);
    //     console.log("x:", x);
    //     uint256 gasStart = gasleft();
    //     uint256 y = quadraticInverse(x, y0, A, B, Cy);
    //     uint256 gasUsed = gasStart - gasleft();
    //     console.log("Gas used:", gasUsed);
    //     console.log("y:", y);

    //     // uint256 yExact = gInverse(x, px, py, x0, y0, cy);
    //     // console.log("yExact:", yExact);

    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         console.log("Running verify()");
    //         assert(verify(x, y));
    //     }
    // }

    function test_fuzzFInvariantDomain1(uint256 x) public view {
        x = bound(x, 1, x0 - 1);
        uint256 y = f(x, px, py, x0, y0, cx);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

    function test_fuzzFInverseInvariantDomain1(uint256 y) public view {
        y = bound(y, y0 + 1, type(uint112).max);
        uint256 x = fInverse(y, px, py, x0, y0, cx);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

    function test_fuzzFInvariantDomain2(uint256 x) public view {
        x = bound(x, x0 + 1, type(uint112).max);
        uint256 y = fInverse(x, px, py, x0, y0, cy);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

    function test_fuzzFInverseInvariantDomain2(uint256 y) public view {
        y = bound(y, 1, y0 - 1);
        uint256 x = g(y, px, py, x0, y0, cy);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

    function test_fuzzScenario1A(uint256 xIn) public view {
        // ### 1a. Swap `xIn` and remain in domain 1
        // **Calculation steps:**
        // 1. `xNew = x + xIn`
        // 2. `yNew = f(xNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(x + xIn)`
        xIn = bound(xIn, 0, x0 - 2);
        uint256 x = 1;
        uint256 xNew = x + xIn;
        uint256 yNew = f(xNew, px, py, x0, y0, cx);
        // domain check
        assertLe(xNew, x0);
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario1B(uint256 xIn) public view {
        // ### 1b. Swap `xIn` and move to domain 2
        // **Calculation steps:**
        // 1. `xNew = x + xIn`
        // 2. `yNew = gInverse(xNew)`
        // **Invariant check:**
        // `xNew >= g(yNew) = g(gInverse(xNew)) = g(gInverse(x + xIn))`
        xIn = bound(xIn, x0, type(uint112).max);
        uint256 x = 1;
        uint256 xNew = x + xIn;
        uint256 yNew = gInverse(xNew, px, py, x0, y0, cy);
        // domain check
        assertGe(xNew, x0);
        assertLe(yNew, y0);
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario2(uint256 yIn) public view {
        // ### 2. Swap `yIn` and remain in domain 1
        // **Calculation steps:**
        // 1. `yNew = y + yIn`
        // 2. `xNew = fInverse(yNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y + yIn))`
        yIn = bound(yIn, 0, type(uint112).max);
        uint256 y = y0 + 1;
        uint256 yNew = y + yIn;
        uint256 xNew = fInverse(yNew, px, py, x0, y0, cx);
        // domain check
        assertLe(xNew, x0);
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario3(uint256 xOut) public view {
        // ### 3. Swap `xOut` and remain in domain 1
        // **Calculation steps:**
        // 1. `xNew = x - xOut`
        // 2. `yNew = f(xNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(x - xOut)`
        xOut = bound(xOut, 0, x0 - 2);
        uint256 x = x0 - 1;
        uint256 xNew = x - xOut;
        uint256 yNew = f(xNew, px, py, x0, y0, cx);
        // domain check
        assertLe(xNew, x0);
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario4A(uint256 yOut) public view {
        // ### 4a. Swap `yOut` and remain in domain 1
        // **Calculation steps:**
        // 1. `yNew = y - yOut`
        // 2. `xNew = fInverse(yNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y - yOut))`
        yOut = bound(yOut, 0, type(uint112).max - (y0 + 1));
        uint256 y = type(uint112).max;
        uint256 yNew = y - yOut;
        uint256 xNew = fInverse(yNew, px, py, x0, y0, cx);
        // domain check
        assertLe(xNew, x0);
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario4B(uint256 yOut) public view {
        // ### 4b. Swap `yOut` and move to domain 2
        // **Calculation steps:**
        // 1. `yNew = y - yOut`
        // 2. `xNew = g(yNew)`
        // **Invariant check:**
        // `xNew >= g(yNew) = g(y - yOut)`
        yOut = bound(yOut, 1, y0 - 1);
        uint256 y = y0;
        uint256 yNew = y - yOut;
        uint256 xNew = g(yNew, px, py, x0, y0, cy);
        // domain check
        assertGe(xNew, x0);
        assertLe(yNew, y0);
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario5(uint256 xIn) public view {
        // ### 5. Swap `xIn` and remain in domain 2
        // **Calculation steps:**
        // 1. `xNew = x + xIn`
        // 2. `yNew = gInverse(xNew)`
        // **Invariant check:**
        // `xNew >= g(yNew) = g(gInverse(xNew)) = g(gInverse(x + xIn))`
        xIn = bound(xIn, 0, type(uint112).max - 1);
        uint256 x = x0 + 1;
        uint256 xNew = x + xIn;
        uint256 yNew = gInverse(xNew, px, py, x0, y0, cy);
        // domain check
        assertGe(xNew, x0);
        assertLe(yNew, y0);
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario6a(uint256 yIn) public view {
        // ### 6a. Swap `yIn` and remain in domain 2
        // **Calculation steps:**
        // 1. `yNew = y + yIn`
        // 2. `xNew = g(yNew)`
        // **Invariant check:**
        // `xNew >= g(yNew) = g(y + yIn)`
        yIn = bound(yIn, 0, y0 - 2);
        uint256 y = 1;
        uint256 yNew = y + yIn;
        uint256 xNew = g(yNew, px, py, x0, y0, cy);
        // domain check
        assertGe(xNew, x0);
        assertLe(yNew, y0);
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario6b(uint256 yIn) public view {
        // ### 6b. Swap `yIn` and move to domain 1
        // **Calculation steps:**
        // 1. `yNew = y + yIn`
        // 2. `xNew = fInverse(yNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y + yIn))`
        yIn = bound(yIn, 1, type(uint112).max);
        uint256 y = y0;
        uint256 yNew = y + yIn;
        uint256 xNew = fInverse(yNew, px, py, x0, y0, cx);
        // domain check
        assertLe(xNew, x0);
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario7a(uint256 xOut) public view {
        // ### 7a. Swap `xOut` and remain in domain 2
        // **Calculation steps:**
        // 1. `xNew = x - xOut`
        // 2. `yNew = gInverse(xNew)`
        // **Invariant check:**
        // `xNew >= g(xNew) = g(x - xOut)`
        xOut = bound(xOut, 0, type(uint112).max - x0 - 1);
        uint256 x = type(uint112).max;
        uint256 xNew = x - xOut;
        uint256 yNew = gInverse(xNew, px, py, x0, y0, cy);
        // domain check
        assertGe(xNew, x0);
        assertLe(yNew, y0);
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario7b(uint256 xOut) public view {
        // ### 7b. Swap `xOut` and move to domain 1
        // **Calculation steps:**
        // 1. `xNew = x - xOut`
        // 2. `yNew = f(xNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(x - xOut)`
        xOut = bound(xOut, 0, x0 - 2);
        uint256 x = x0 - 1;
        uint256 xNew = x - xOut;
        uint256 yNew = f(xNew, px, py, x0, y0, cx);
        // domain check
        assertLe(xNew, x0);
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario8(uint256 yOut) public view {
        // ### 8. Swap `yOut` and remain in domain 2
        // **Calculation steps:**
        // 1. `yNew = y - yOut`
        // 2. `xNew = g(yNew)`
        // **Invariant check:**
        // `xNew >= g(yNew) = g(y - yOut)`
        yOut = bound(yOut, 0, y0 - 2);
        uint256 y = y0 - 1;
        uint256 yNew = y - yOut;
        uint256 xNew = g(yNew, px, py, x0, y0, cy);
        // domain check
        assertGe(xNew, x0);
        assertLe(yNew, y0);
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }
}
