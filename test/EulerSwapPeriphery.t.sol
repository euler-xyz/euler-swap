// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapHarness} from "./harness/EulerSwapHarness.sol";

import "forge-std/console.sol";

contract EulerSwapPeripheryTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;
    EulerSwapHarness public eulerSwapHarness;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

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

    function test_fInverseFuzz(uint256 x) public {
        x = bound(x, 2, 50e18 - 1); // note that it fails if 1 used as minimum, not an issue since only used in periphery
        uint256 y = eulerSwapHarness.exposedF(x, 1e18, 1e18, 50e18, 50e18, 0.85e18);
        uint256 outX = periphery.fInverse(y, 1e18, 1e18, 50e18, 50e18, 0.85e18);

        // Ensure x is within the expected range
        assertGe(outX, x); // Asserts xOut >= x
        assertLe(outX, x + 1); // Asserts xOut <= x + 1

        // Alternative using assertApproxEqAbs for absolute difference within 1
        assertApproxEqAbs(x, outX, 1);
    }

    function test_quoteExactInput() public {
        uint256 amountIn = 1e18;
        uint256 amountOutBinary =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        console.log("amountOutBinary", amountOutBinary);
        uint256 amountOutExplicit =
            periphery.quoteExactInputExplicit(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        console.log("amountOutExplicit", amountOutExplicit);

        assertEq(amountOutBinary, amountOutExplicit);
    }

    function test_quoteExactOutput() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        console.log("amountIn", amountIn);
        uint256 amountInExplicit =
            periphery.quoteExactOutputExplicit(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        console.log("amountInExplicit", amountInExplicit);

        assertEq(amountIn, amountInExplicit);
    }

    function test_fuzzQuoteExactInput(uint256 amountIn) public {
        amountIn = bound(amountIn, 2, 50e18 - 1);
        uint256 amountOutBinary =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        console.log("amountOutBinary", amountOutBinary);
        uint256 amountOutExplicit =
            periphery.quoteExactInputExplicit(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        console.log("amountOutExplicit", amountOutExplicit);

        assertEq(amountOutBinary, amountOutExplicit);
    }

    function test_fuzzQuoteExactOutput(uint256 amountOut) public {
        amountOut = bound(amountOut, 2, 50e18 - 1);
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        console.log("amountIn", amountIn);
        uint256 amountInExplicit =
            periphery.quoteExactOutputExplicit(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        console.log("amountInExplicit", amountInExplicit);

        assertEq(amountIn, amountInExplicit);
    }
}
