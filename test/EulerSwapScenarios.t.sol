// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapScenarioTest is Test {
    // Global params
    uint256 x0 = 50.343e18;
    uint256 y0 = 20.434e18;
    uint256 px = 1e18;
    uint256 py = 21e18;
    uint256 cx = 0.89343e18;
    uint256 cy = 0.23231e18;

    function verify(uint256 newReserve0, uint256 newReserve1) public view returns (bool) {
        if (newReserve0 > type(uint112).max || newReserve1 > type(uint112).max) return false;

        if (newReserve0 >= x0) {
            if (newReserve1 >= y0) return true;
            return
                newReserve0 >= f(newReserve1, py, px, y0, x0, cy);
        } else {
            if (newReserve1 < y0) return false;
            return
                newReserve1 >= f(newReserve0, px, py, x0, y0, cx);
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

    function quadraticInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        public
        pure
        returns (uint256)
    {
        if(y == y0) {
            return x0;
        }
        
        uint256 xN = x0 * 1e18 / 2e18;
        
        uint256 A = c;
        int256 B = getB(y, px, py, x0, y0, c);
        int256 C = -((int256(1e18) - int256(c)) * int256(Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil))) / 1e18;


        console.log("y:", y);
        console.log();

        for (uint256 i = 0; i < 10; i++) {
            console.log("xN:", xN);
            console.log("yN:", f(xN, px, py, x0, y0, c));
            console.log();
            int256 xNPlus1 = int256(xN) - (quadratic(xN, A, B, C) * 1e18) / quadraticDerivative(xN, A, B); // Scaled division for precision
            if (xNPlus1 < 0) {
                xNPlus1 = 1;
            } else if (xNPlus1 > int256(x0) - 1) {
                xNPlus1 = int256(x0) - 1;
            }
            if (abs(int256(xN) - xNPlus1) < 1) break; // Stop if change is too small            
            xN = uint256(xNPlus1);
        }
        // if y is greater than our predicted y, the method will not pass the invariant check
        console.log("Micro-optimise:");        
        // while(y < f(xN, px, py, x0, y0, c)) {
        //     xN = xN - 1;
        //     console.log("xN:", xN);
        //     console.log("yN:", f(xN, px, py, x0, y0, c));
        //     console.log();
        // }
        console.log("xF:", xN);
        console.log("yN:", f(xN, px, py, x0, y0, c));
        console.log();
        return xN;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            require(v <= type(uint248).max, "Help!");
            return y0 + (v + (py - 1)) / py;
        }
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
        // return quadraticInverse(x, py, px, y0, x0, c);
    }

    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {

        int256 B = int256(Math.mulDiv(py, y - y0, px, Math.Rounding.Ceil) + x0) - int256(Math.mulDiv(x0, 2 * c, 1e18, Math.Rounding.Floor));

        // B^2 component, using FullMath for overflow safety
        uint256 absB = B < 0 ? uint256(-B) : uint256(B);
        uint256 squaredB = Math.mulDiv(absB, absB, 1e18, Math.Rounding.Ceil);

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
        return Math.mulDiv(uint256(int256(sqrt) - B), 1e18, 2 * c, Math.Rounding.Ceil);
    }

    function test_FInverse() public view {
        uint256 y = 139780697298741147996;
        console.log("y:", y);

        uint256 gasStart = gasleft();
        uint256 x = fInverse(y, px, py, x0, y0, cx);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas:", gasUsed);
        console.log("x:", x);

        if (x <= type(uint112).max && y <= type(uint112).max) {
            console.log("In range (x, y)");
            assert(verify(x, y));
        }
    }

    function test_GInverse() public view {
        uint256 x = 139780697298741147996;
        console.log("x:", x);

        uint256 gasStart = gasleft();
        uint256 y = gInverse(x, px, py, x0, y0, cy);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas:", gasUsed);
        console.log("y:", y);

        if (x <= type(uint112).max && y <= type(uint112).max) {
            console.log("In range (x, y)");
            assert(verify(x, y));
        }
    }

    // function testDomain2() public view {
    //     uint256 xInit = 139780697298741147996;
    //     uint256 y = gInverse(xInit, px, py, x0, y0, cy);
    //     uint256 x = g(y, px, py, x0, y0, cy);
    //     uint256 y2 = gInverse(x, px, py, x0, y0, cy);
    //     console.log(xInit);
    //     console.log(y);    
    //     console.log(x);
    //     console.log(y2);

    //     if (x <= type(uint112).max && y <= type(uint112).max) {
    //         console.log("In range (x, y), so running verify");
    //         assert(verify(x, y));
    //     }
    // }

    function test_fuzzF(uint256 x) public view {
        x = bound(x, 1, x0 - 1);
        uint256 y = f(x, px, py, x0, y0, cx);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

    function test_fuzzFInverse(uint256 y) public view {
        y = bound(y, y0 + 2, type(uint112).max - y0 - 1);
        uint256 x = fInverse(y, px, py, x0, y0, cx);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

    function test_fuzzG(uint256 y) public view {
        y = bound(y, 1, y0 - 1);
        uint256 x = g(y, px, py, x0, y0, cy);
        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }

    function test_fuzzGInverse(uint256 x) public view {
        x = bound(x, x0 + 2, type(uint112).max - x0 - 1);
        uint256 y = gInverse(x, px, py, x0, y0, cy);
        uint256 xCalc = g(y, px, py, x0, y0, cy);
        
        console.log(x, y, xCalc);

        if (x <= type(uint112).max && y <= type(uint112).max) {
            assert(verify(x, y));
        }
    }


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
