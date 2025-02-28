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
        uint256 x = 0.45435e18;
        uint256 y = eulerSwap.f(x, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        uint256 outX = eulerSwap.fInverse(y, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        console.log("x: ", x);
        console.log("y: ", y);
        console.log("xOut: ", outX);  
        assertEq(x, outX);  
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
