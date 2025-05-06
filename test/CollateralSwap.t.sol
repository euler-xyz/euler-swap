// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract CollateralSwap is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        // We're going to make eTST3 a borrowable asset, using eTST and eTST2 as collateral.
        // Swaps will re-allocate between the collaterals, without touching the eTST3 loan.

        // 0 out the existing LTVs
        eTST.setLTV(address(eTST2), 0, 0, 0);
        eTST2.setLTV(address(eTST), 0, 0, 0);
        eTST.setLTV(address(eTST3), 0, 0, 0);

        // Set new LTVs
        eTST3.setLTV(address(eTST), 0.9e4, 0.9e4, 0);
        eTST3.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        // Mint another 40 of the collateral assets (50 total in each)
        mintAndDeposit(holder, eTST, 40e18);
        mintAndDeposit(holder, eTST2, 40e18);

        // Borrow 80 TST3
        vm.startPrank(holder);

        evc.enableCollateral(holder, address(eTST));
        evc.enableCollateral(holder, address(eTST2));
        evc.enableController(holder, address(eTST3));

        eTST3.borrow(80e18, address(0xdead)); // burning simulates a looped position

        vm.stopPrank();

        eulerSwap = createEulerSwap(49e18, 49e18, 0, 1e18, 1e18, 0.9e18, 0.9e18);
    }

    function test_collateralSwap() public {
        uint256 amountIn;
        uint256 amountOut;

        // Direction 1

        amountIn = 40e18;
        amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 33.1051e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        assertApproxEqAbs(eTST.balanceOf(holder), 50e18 + 40e18, 0.0001e18);
        assertApproxEqAbs(eTST2.balanceOf(holder), 50e18 - 33.1051e18, 0.0001e18);

        // Direction 2

        amountIn = 70e18;
        amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);
        assertApproxEqAbs(amountOut, 71.336e18, 0.0001e18);

        assetTST2.mint(address(this), amountIn);
        assetTST2.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(amountOut, 0, address(this), "");

        assertApproxEqAbs(eTST.balanceOf(holder), 50e18 + 40e18 - 71.336e18, 0.0001e18);
        assertApproxEqAbs(eTST2.balanceOf(holder), 50e18 - 33.1051e18 + 70e18, 0.0001e18);
    }
}
