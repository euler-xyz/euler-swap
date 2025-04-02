// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract FeesTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.9e18, 0.9e18);
    }

    function test_fees_exactIn() public monotonicHolderNAV {
        int256 origNav = getHolderNAV();
        uint256 fee = 0.05e18;

        // No fees

        uint256 amountInNoFees = 1e18;
        uint256 amountOutNoFees =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountInNoFees);
        assertApproxEqAbs(amountOutNoFees, 0.9983e18, 0.0001e18);

        // With fees: Increase input amount so that corresponding output amount matches

        eulerSwap = createEulerSwap(60e18, 60e18, fee, 1e18, 1e18, 0.9e18, 0.9e18);

        uint256 amountIn = amountInNoFees * 1e18 / (1e18 - fee);
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, amountOutNoFees, 1); // Same except for possible rounding down by 1

        // Actually execute swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        // Pulling out one extra reverts...
        // NOTE: one extra might not revert if the quote was an underestimate, so pulling out one extra should not be expected to revert on all occasions.
        // vm.expectRevert(EulerSwap.CurveViolation.selector);
        // eulerSwap.swap(0, amountOut + 1, address(this), "");

        // Just right:

        eulerSwap.swap(0, amountOut, address(this), "");

        // Swapper received their quoted amount:

        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        // eulerSwap instance is empty:

        assertEq(assetTST.balanceOf(address(eulerSwap)), 0);
        assertEq(assetTST2.balanceOf(address(eulerSwap)), 0);

        // Holder's NAV increased by fee amount, plus slightly extra because we are not at curve equilibrium point

        assertGt(getHolderNAV(), origNav + int256(amountIn - amountInNoFees));
        assertEq(eTST.balanceOf(address(holder)), 10e18 + amountIn);
        assertEq(eTST2.balanceOf(address(holder)), 10e18 - amountOut);
    }

    function test_fees_exactOut() public monotonicHolderNAV {
        int256 origNav = getHolderNAV();
        uint256 fee = 0.05e18;

        // No fees

        uint256 amountOut = 1e18;
        uint256 amountInNoFees =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountInNoFees, 1.0017e18, 0.0001e18);

        // With fees: Increase input amount so output amount stays same

        eulerSwap = createEulerSwap(60e18, 60e18, fee, 1e18, 1e18, 0.9e18, 0.9e18);

        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountIn, amountInNoFees * 1e18 / (1e18 - fee), 1); // Same except for possible rounding up by 1

        // Actually execute swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        // Pulling out one extra reverts...

        vm.expectRevert(EulerSwap.CurveViolation.selector);
        eulerSwap.swap(0, amountOut + 1, address(this), "");

        // Just right:

        eulerSwap.swap(0, amountOut, address(this), "");

        // Swapper received their quoted amount:

        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        // eulerSwap instance is empty:

        assertEq(assetTST.balanceOf(address(eulerSwap)), 0);
        assertEq(assetTST2.balanceOf(address(eulerSwap)), 0);

        // Holder's NAV increased by fee amount, plus slightly extra because we are not at curve equilibrium point

        assertGt(getHolderNAV(), origNav + int256(amountIn - amountInNoFees));
        assertEq(eTST.balanceOf(address(holder)), 10e18 + amountIn);
        assertEq(eTST2.balanceOf(address(holder)), 10e18 - amountOut);
    }
}
