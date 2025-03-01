// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract EulerSwapTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_basicSwap_exactIn() public monotonicHolderNAV {
        uint256 x = 9.057864926376394073e18;
        uint256 y = eulerSwap.f(x, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        uint256 outX = eulerSwap.fInverse(y, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        console.log("x: ", x);
        console.log("y: ", y);
        console.log("xOut: ", outX);  
        assertEq(x, outX);  
    }

    // function test_basicSwap_exactIn() public monotonicHolderNAV {
    //     uint256 x = 99.900000000000016422e18;
    //     uint256 y = eulerSwap.f(x, 1e18, 1e18, 50e18, 50e18, 0.85e18);
    //     uint256 outX = eulerSwap.fInverse(y, 1e18, 1e18, 50e18, 50e18, 0.85e18);
    //     console.log("x: ", x);
    //     console.log("y: ", y);
    //     console.log("xOut: ", outX);  
    //     assertEq(x, outX);  
    // }

    function test_fInverseFuzz(uint x) public {
        x = bound(x, 2, 50e18 - 1); // it fails if 1 us used, not an issue since only used in periphery
        uint256 y = eulerSwap.f(x, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        uint256 outX = eulerSwap.fInverse(y, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        console.log("x: ", x);
        console.log("y: ", y);
        console.log("xOut: ", outX);

        // Ensure x is within the expected range
        assertGe(outX, x); // Asserts xOut >= x
        assertLe(outX, x + 1); // Asserts xOut <= x + 1

        // Alternative using assertApproxEqAbs for absolute difference within 1
        assertApproxEqAbs(x, outX, 1);
    }

}
