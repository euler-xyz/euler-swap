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
    uint256 x = 25e18;

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

    function test_Scenario() public {
        uint256 x = 45e18;
        uint256 y = f(x, px, py, x0, y0, cx);
        assertGe(y, y0);
    }

    function test_fuzzScenario1A(uint256 xIn) public {
        // ## 1a. Swap `xIn` and remain in domain 1
        // **Calculation steps:**
        // 1. `xNew = x + xIn`
        // 2. `yNew = f(xNew)`
        // **Invariant check:**
        // `yNew >= f(xNew) = f(x + xIn)`
        xIn = bound(xIn, 0, x0 - x - 1); 
        uint256 x = 1;
        uint256 xNew = x + xIn;
        uint256 yNew = f(xNew, px, py, x0, y0, cx);
        assertGe(yNew, y0);
        assertGe(yNew, f(xNew, px, py, x0, y0, cx));
    }

    function test_fuzzScenario1B(uint256 xIn) public {
        // ## 1b. Swap `xIn` and move to domain 2
        // **Calculation steps:**
        // 1. `xNew = x + xIn`
        // 2. `yNew = fInverse(xNew)`
        // **Invariant check:**
        // `xNew >= g(yNew) = g(fInverse(xNew)) = g(fInverse(x + xIn))`
        xIn = bound(xIn, x0, x0 * x0 / 1e18);
        uint256 x = 1;
        uint256 xNew = x + xIn;
        uint256 yNew = fInverse(xNew, px, py, x0, y0, cy);
        assertLe(yNew, y0);
        assertGe(xNew, g(yNew, px, py, x0, y0, cy));
    }
}
