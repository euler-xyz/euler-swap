// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol"; // Import console.sol for logging
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwapScenarioTest is Test {
    function f(uint256 x, uint256 c) internal pure returns (uint256) {
        return ((1e18 - c) * 1e18) / x + (c * (2e18 - x)) / 1e18;
    }

    function fInverse(uint256 y, uint256 c) public pure returns (uint256) {
        int256 A = int256(c);
        int256 B = int256(y) - int256(2 * c);
        int256 C = -int256(1e18 - c);

        // Calculate discriminant: b^2 - 4ac
        int256 discriminant = B * B - 4 * A * C;

        // sqrt discriminant (scaled to 1e18)
        uint256 sqrtDisc = Math.sqrt(uint256(discriminant));

        // Numerator: -b + sqrt(...)
        int256 numerator = -B + int256(sqrtDisc);

        // Denominator: 2a
        int256 denominator = 2 * A;

        // x = numerator / denominator
        uint256 x = uint256((numerator * 1e18) / denominator);

        return x;
    }

    function getY(uint256 x, uint256 p, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        uint256 scaledX = (x * 1e18) / x0;
        return y0 + Math.mulDiv(p * x0, f(scaledX, c) - 1e18, 1e36);
    }

    function getX(uint256 y, uint256 p, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        uint256 scaledY = (y - y0) * 1e36 / (p * x0) + 1e18;
        console.log("scaledY", scaledY);
        return fInverse(scaledY, c);
    }

    function test_F() public {
        // Params
        uint256 p = 2e18;
        uint256 x0 = 50e18;
        uint256 y0 = 50e18;
        uint256 cx = 0.5e18;

        uint256 smallestX = (x0 + 1e18 - 1) / 1e18;
        console.log("smallestX", smallestX);

        console.log("x0", x0);
        console.log("y0", y0);
        console.log("p", p);
        console.log("cx", cx);

        uint256 x = 25e18;
        console.log("x", x);

        uint256 y = getY(x, p, x0, y0, cx);
        console.log("y", y);
    }

    function test_fuzzF(uint256 x, uint256 p, uint256 x0, uint256 y0, uint256 cx) public {
        // Params
        p = bound(p, 1, 1e36);
        x0 = 50e18;
        y0 = bound(y0, 0, 50e18);
        cx = bound(cx, 1, 1e18);

        console.log("x0", x0);
        console.log("y0", y0);
        console.log("p", p);
        console.log("cx", cx);

        uint256 smallestX = (x0 + 1e18 - 1) / 1e18;
        console.log("smallestX", smallestX);

        x = bound(x, smallestX, x0 - 1);
        console.log("x", x);

        uint256 y = getY(x, p, x0, y0, cx);
        console.log("y", y);
    }

    function test_FInverse() public {
        // Params
        uint256 p = 2e18;
        uint256 x0 = 50e18;
        uint256 y0 = 50e18;
        uint256 cx = 0.5e18;

        uint256 smallestX = (x0 + 1e18 - 1) / 1e18;
        console.log("smallestX", smallestX);

        console.log("x0", x0);
        console.log("y0", y0);
        console.log("p", p);
        console.log("cx", cx);

        uint256 y = 100e18;
        console.log("y", y);

        uint256 x = fInverse(y, cx);
        console.log("x", x);

        uint256 x2 = getX(y, p, x0, y0, cx);
        console.log("x2", x2);
    }

    function test_fuzzFInverse(uint256 y, uint256 p, uint256 x0, uint256 y0, uint256 cx) public {
        // Params
        p = bound(p, 1, 1e36);
        x0 = 50e18;
        y0 = bound(y0, 0, 50e18);
        cx = bound(cx, 1, 1e18);

        console.log("x0", x0);
        console.log("y0", y0);
        console.log("p", p);
        console.log("cx", cx);

        y = bound(y, 1e18 + 1, type(uint112).max);
        console.log("y", y);

        uint256 x = fInverse(y, cx);
        console.log("x", x);
    }
}
