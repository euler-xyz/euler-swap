// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";

contract PeripheryTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_SwapExactIn() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        periphery.swapExactIn(address(eulerSwap), address(assetTST), address(assetTST2), amountIn, anyone, amountOut, 0);
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), amountOut);
    }

    function test_SwapExactIn_AmountOutLessThanMin() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        vm.expectRevert(EulerSwapPeriphery.AmountOutLessThanMin.selector);
        periphery.swapExactIn(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, anyone, amountOut + 1, 0
        );
        vm.stopPrank();
    }

    function test_SwapExactOut() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        periphery.swapExactOut(
            address(eulerSwap), address(assetTST), address(assetTST2), amountOut, anyone, amountIn, 0
        );
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), amountOut);
    }

    function test_SwapExactOut_AmountInMoreThanMax() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        vm.expectRevert(EulerSwapPeriphery.AmountInMoreThanMax.selector);
        periphery.swapExactOut(
            address(eulerSwap), address(assetTST), address(assetTST2), amountOut * 2, anyone, amountIn, 0
        );
        vm.stopPrank();
    }

    function test_SwapAltReceiver() public {
        address altReceiver = address(1234);

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        periphery.swapExactIn(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, altReceiver, amountOut, 0
        );
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), 0);
        assertEq(assetTST2.balanceOf(altReceiver), amountOut);
    }

    function test_SwapDeadline() public {
        skip(1000);

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);

        vm.expectRevert(EulerSwapPeriphery.DeadlineExpired.selector);
        periphery.swapExactIn(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, anyone, amountOut, block.timestamp - 1
        );

        periphery.swapExactIn(
            address(eulerSwap), address(assetTST), address(assetTST2), amountIn, anyone, amountOut, block.timestamp + 1
        );
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), amountOut);
    }

    function test_SwapZeroAmounts() public view {
        assertEq(periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), 0), 0);
        assertEq(periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), 0), 0);

        assertEq(periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 0), 0);
        assertEq(periphery.quoteExactOutput(address(eulerSwap), address(assetTST2), address(assetTST), 0), 0);
    }
}
