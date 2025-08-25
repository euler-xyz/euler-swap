// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

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

    function challengeAux(TestERC20 t1, TestERC20 t2, bool exactIn) internal {
        // Quotes OK:

        uint256 amountIn;
        uint256 amountOut;

        if (exactIn) {
            amountIn = 500e18;
            amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amountIn);
            assertApproxEqAbs(amountOut, 499.95e18, 0.01e18);
        } else {
            amountOut = 500e18;
            amountIn =
                periphery.quoteExactOutput(address(eulerSwap), address(t1), address(t2), amountOut);
            assertApproxEqAbs(amountIn, 500.05e18, 0.01e18);
        }

        // But swap fails due to E_AccountLiquidity

        {
            uint256 snapshot = vm.snapshotState();

            t1.mint(address(this), amountIn);
            t1.transfer(address(eulerSwap), amountIn);

            vm.expectRevert(E_AccountLiquidity.selector);
            if (t1 == assetTST) eulerSwap.swap(0, amountOut, address(this), "");
            else eulerSwap.swap(amountOut, 0, address(this), "");

            vm.revertToState(snapshot);
        }

        assertEq(eulerSwapFactory.poolsLength(), 1);

        // So let's challenge it:

        t1.mint(address(this), amountIn); // challenge funds
        t1.approve(address(eulerSwapFactory), amountIn);
        assertEq(t1.balanceOf(address(this)), amountIn);

        eulerSwapFactory.challengePool(
            address(eulerSwap), address(t1), address(t2), exactIn ? amountIn : amountOut, exactIn, address(5555)
        );

        assertEq(t1.balanceOf(address(this)), amountIn); // funds didn't move
        assertEq(eulerSwapFactory.poolsLength(), 0); // removed from lists
        assertEq(address(5555).balance, 0.123e18); // recipient received bond

        // Verify that uninstall still works:

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), false);
        vm.prank(holder);
        eulerSwapFactory.uninstallPool();
    }

    function test_basicChallenge12in() public {
        challengeAux(assetTST, assetTST2, true);
    }

    function test_basicChallenge21in() public {
        challengeAux(assetTST2, assetTST, true);
    }

    function test_basicChallenge12out() public {
        challengeAux(assetTST, assetTST2, false);
    }

    function test_basicChallenge21out() public {
        challengeAux(assetTST2, assetTST, false);
    }

    function test_bondReturnedOnUninstall() public {
        assertEq(holder.balance, 0);

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), false);
        vm.prank(holder);
        eulerSwapFactory.uninstallPool();

        assertEq(holder.balance, 0.123e18);
    }
}
