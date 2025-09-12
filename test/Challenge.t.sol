// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {EulerSwapRegistry} from "../src/EulerSwapRegistry.sol";
import "../src/interfaces/IEulerSwapHookTarget.sol";
import "../src/libraries/SwapLib.sol";
import "evk/EVault/shared/lib/RevertBytes.sol";

contract ChallengeTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

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
            amountOut = periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amountIn);
            assertApproxEqAbs(amountOut, 499.95e18, 0.01e18);
        } else {
            amountOut = 500e18;
            amountIn = periphery.quoteExactOutput(address(eulerSwap), address(t1), address(t2), amountOut);
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

        assertEq(eulerSwapRegistry.poolsLength(), 1);

        // So let's challenge it:

        t1.mint(address(this), amountIn); // challenge funds
        t1.approve(address(eulerSwapRegistry), amountIn);
        assertEq(t1.balanceOf(address(this)), amountIn);

        eulerSwapRegistry.challengePool(
            address(eulerSwap), address(t1), address(t2), exactIn ? amountIn : amountOut, exactIn, address(5555)
        );

        assertEq(t1.balanceOf(address(this)), amountIn); // funds didn't move
        assertEq(eulerSwapRegistry.poolsLength(), 0); // removed from lists
        assertEq(address(5555).balance, 0.123e18); // recipient received bond

        // Verify that unregister still works:

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), false);
        vm.prank(holder);
        eulerSwapRegistry.unregisterPool();
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
        eulerSwapRegistry.unregisterPool();

        assertEq(holder.balance, 0.123e18);
    }

    function test_challengeHookRevert() public {
        vm.deal(holder, 0.123e18);
        eulerSwap = createEulerSwap(10e18, 10e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);

        uint256 amountIn = 5e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        // Plain swap is OK:

        {
            uint256 snapshot = vm.snapshotState();

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);

            eulerSwap.swap(0, amountOut, address(this), "");

            vm.revertToState(snapshot);
        }

        // Reconfigure to have a beforeSwap hook that fails

        setHook(EULER_SWAP_HOOK_BEFORE_SWAP, 0, 0);

        {
            uint256 snapshot = vm.snapshotState();

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);

            vm.expectRevert(
                abi.encodeWithSelector(
                    SwapLib.HookError.selector, EULER_SWAP_HOOK_BEFORE_SWAP, bytes("not gonna happen")
                )
            );
            eulerSwap.swap(0, amountOut, address(this), "");

            vm.revertToState(snapshot);
        }

        // Non-swap errors are not challengeable, for example insufficient input tokens:

        vm.expectRevert(EulerSwapRegistry.ChallengeSwapNotLiquidityFailure.selector);
        eulerSwapRegistry.challengePool(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, true, address(5555)
        );

        // Give the input tokens and challenge it:

        assetTST.mint(address(this), amountIn); // challenge funds
        assetTST.approve(address(eulerSwapRegistry), amountIn);

        assertEq(eulerSwapRegistry.poolsLength(), 1);

        eulerSwapRegistry.challengePool(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, true, address(5555)
        );

        assertEq(eulerSwapRegistry.poolsLength(), 0); // removed from lists
    }

    function test_challengeHookRevert2() public {
        vm.deal(holder, 0.123e18);
        eulerSwap = createEulerSwap(10e18, 10e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);

        uint256 amountIn = 5e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        // Plain swap is OK:

        {
            uint256 snapshot = vm.snapshotState();

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);

            eulerSwap.swap(0, amountOut, address(this), "");

            vm.revertToState(snapshot);
        }

        // Reconfigure so output asset transfers fail

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        assetTST2.configure("transfer/revert", bytes("0"));

        vm.expectRevert(bytes("revert behaviour"));
        eulerSwap.swap(0, amountOut, address(this), "");

        // But this error is not challengeable

        vm.expectRevert(EulerSwapRegistry.ChallengeSwapNotLiquidityFailure.selector);
        eulerSwapRegistry.challengePool(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, true, address(5555)
        );
    }

    function beforeSwap(uint256, uint256, address, address) external pure {
        RevertBytes.revertBytes("not gonna happen");
    }

    function setHook(uint8 hookedOps, uint64 fee0Param, uint64 fee1Param) internal {
        PoolConfig memory pc = getPoolConfig(eulerSwap);

        pc.dParams.fee0 = fee0Param;
        pc.dParams.fee1 = fee1Param;
        pc.dParams.swapHookedOperations = hookedOps;
        pc.dParams.swapHook = address(this);

        reconfigurePool(eulerSwap, pc);
    }
}
