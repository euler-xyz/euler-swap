// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapScenarioTest is Test {
    // Global params
    uint256 x0 = 50e18;
    uint256 y0 = 50e18;
    uint256 px = 1e18;
    uint256 py = 1e18;
    uint256 cx = 0.5e18;
    uint256 cy = 0.5e18;

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

    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
        return y0 + (v + (py - 1)) / py;
    }

    function g(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        return f(y, py, px, y0, x0, c);
    }

    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        public
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

    function test_specificScenario() public view {
        uint256 x = 139780697298741147996;
        uint256 y = fInverse(x, px, py, x0, y0, cy);
        console.log(x);
        console.log(y);
        console.log(verify(x, y));
        uint256 xNew = g(y, px, py, x0, y0, cy);
        console.log(xNew);
        assertApproxEqAbs(x, xNew, 1000);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

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
        // ## 1a. Swap `xIn` and remain in domain 1
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
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario1B(uint256 xIn) public view {
        // ## 1b. Swap `xIn` and move to domain 2
        // **Calculation steps:**
        // 1. `xNew = x + xIn`
        // 2. `yNew = fInverse(xNew)`
        // **Invariant check:**
        // `xNew >= g(yNew) = g(fInverse(xNew)) = g(fInverse(x + xIn))`
        xIn = bound(xIn, x0, type(uint112).max);
        uint256 x = 1;
        uint256 xNew = x + xIn;
        uint256 yNew = fInverse(xNew, px, py, x0, y0, cy);
        // domain check
        assertLe(yNew, y0);
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario2(uint256 yIn) public view {
        // ## 2. Swap `yIn` and remain in domain 1
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
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario3(uint256 xOut) public view {
        // ## 3. Swap `xOut` and remain in domain 1
        // **Calculation steps:**
        // 1. `xNew = x - xOut`
        // 2. `yNew = f(xNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(x - xOut)`
        xOut = bound(xOut, 0, x0 - 2);
        uint256 x = x0 - 1;
        uint256 xNew = x - xOut;
        uint256 yNew = f(xNew, px, py, x0, y0, cy);
        // domain check
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario4A(uint256 yOut) public view {
        // ## 4a. Swap `yOut` and remain in domain 1
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
        assertGe(yNew, y0);
        // direct invariant check
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }

    function test_fuzzScenario4B(uint256 yOut) public view {
        // ## 4b. Swap `yOut` and move to domain 2
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
        // direct invariant check
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
        // main ivariant check
        if (xNew <= type(uint112).max && yNew <= type(uint112).max) {
            assert(verify(xNew, yNew));
        }
    }
}
