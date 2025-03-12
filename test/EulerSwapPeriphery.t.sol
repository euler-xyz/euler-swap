// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapHarness} from "./harness/EulerSwapHarness.sol";

contract EulerSwapPeripheryTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;
    EulerSwapHarness public eulerSwapHarness;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

        IEulerSwap.Params memory params = getEulerSwapParams(50e18, 50e18, 0.4e18);
        IEulerSwap.CurveParams memory curveParams =
            IEulerSwap.CurveParams({priceX: 1e18, priceY: 1e18, concentrationX: 0.85e18, concentrationY: 0.85e18});

        eulerSwapHarness = new EulerSwapHarness(params, curveParams); // Use the mock EulerSwap contract with a public f() function
    }

    function test_SwapExactIn() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        periphery.swapExactIn(address(eulerSwap), address(assetTST), address(assetTST2), amountIn, amountOut);
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
        periphery.swapExactIn(address(eulerSwap), address(assetTST), address(assetTST2), amountIn, amountOut + 1);
        vm.stopPrank();
    }

    function test_SwapExactOut() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(periphery), amountIn);
        periphery.swapExactOut(address(eulerSwap), address(assetTST), address(assetTST2), amountOut, amountIn);
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
        periphery.swapExactOut(address(eulerSwap), address(assetTST), address(assetTST2), amountOut * 2, amountIn);
        vm.stopPrank();
    }
}
