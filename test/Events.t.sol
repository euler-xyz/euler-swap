// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import "forge-std/console.sol";

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import "../src/libraries/SwapLib.sol";

contract Events is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        uint64 myFee = 0.015e18;
        eulerSwap = createEulerSwap(60e18, 60e18, myFee, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_events_exactInNormal() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9825e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(eulerSwap), amountIn);

        {
            uint256 amountInWithoutFee = amountIn - (amountIn * eulerSwap.getDynamicParams().fee0 / 1e18);
            (uint112 r0, uint112 r1,) = eulerSwap.getReserves();
            vm.expectEmit(true, true, true, true);
            emit SwapLib.Swap(
                address(this),
                amountInWithoutFee,
                0,
                0,
                amountOut,
                amountIn - amountInWithoutFee,
                0,
                r0 + uint112(amountInWithoutFee),
                r1 - uint112(amountOut),
                address(1234)
            );
        }

        eulerSwap.swap(0, amountOut, address(1234), "");

        assertEq(assetTST2.balanceOf(address(1234)), amountOut);
    }

    function test_events_exactInReverse() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);
        assertApproxEqAbs(amountOut, 0.9753e18, 0.0001e18);

        assetTST2.mint(address(this), amountIn);

        assetTST2.transfer(address(eulerSwap), amountIn);

        {
            uint256 amountInWithoutFee = amountIn - (amountIn * eulerSwap.getDynamicParams().fee1 / 1e18);
            (uint112 r0, uint112 r1,) = eulerSwap.getReserves();
            vm.expectEmit(true, true, true, true);
            emit SwapLib.Swap(
                address(this),
                0,
                amountInWithoutFee,
                amountOut,
                0,
                0,
                amountIn - amountInWithoutFee,
                r0 - uint112(amountOut),
                r1 + uint112(amountInWithoutFee),
                address(this)
            );
        }

        eulerSwap.swap(amountOut, 0, address(this), "");

        assertEq(assetTST.balanceOf(address(this)), amountOut);
    }
}
