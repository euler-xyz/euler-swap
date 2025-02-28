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

// IEulerSwap eulerSwap,
//         uint112 reserve0,
//         uint112 reserve1,
//         uint256 amount,
//         bool exactIn,
//         bool asset0IsInput

    function test_basicSwap_exactIn() public monotonicHolderNAV {
        uint256 xIn = 2.3e18;
        uint256 yOut = eulerSwap.f(xIn, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        console.log("xIn: ", xIn);
        console.log("yOut: ", yOut);
        console.log("yIn: ", yOut);
        uint256 outX = eulerSwap.fInverse(yOut, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        console.log("xOut: ", outX);    
    }

    function test_basicSwap_exactOut() public monotonicHolderNAV {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountIn, 1.0025e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

}
