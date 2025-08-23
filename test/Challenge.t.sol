// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/console.sol";
import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {QuoteLib} from "../src/libraries/QuoteLib.sol";

contract ChallengeTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    error E_AccountLiquidity();

    function setUp() public virtual override {
        super.setUp();

        mintAndDeposit(depositor, eTST, 500e18);
        mintAndDeposit(depositor, eTST2, 500e18);

        vm.deal(holder, 0.123e18);
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);
    }

    function test_basicChallenge() public monotonicHolderNAV {
        // Quotes OK:

        uint256 amountIn = 500e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 499.95e18, 0.01e18);

        // But swap fails due to E_AccountLiquidity

        {
            uint256 snapshot = vm.snapshotState();

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);

            vm.expectRevert(E_AccountLiquidity.selector);
            eulerSwap.swap(0, amountOut, address(this), "");

            vm.revertToState(snapshot);
        }

        assertEq(eulerSwapFactory.poolsLength(), 1);

        // So let's challenge it:

        assetTST.mint(address(this), amountIn); // challenge funds
        assetTST.approve(address(eulerSwapFactory), amountIn);
        assertEq(assetTST.balanceOf(address(this)), amountIn);

        eulerSwapFactory.challengePool(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, true, address(5555)
        );

        assertEq(assetTST.balanceOf(address(this)), amountIn); // funds didn't move
        assertEq(eulerSwapFactory.poolsLength(), 0); // removed from lists
        assertEq(address(5555).balance, 0.123e18); // recipient received bond

        // Verify that uninstall still works:

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), false);
        vm.prank(holder);
        eulerSwapFactory.uninstallPool();
    }
}
