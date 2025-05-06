// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {QuoteLib} from "../src/libraries/QuoteLib.sol";

contract OneSidedCurve is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(0, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_OneSidedCurve() public monotonicHolderNAV {
        // Nothing available
        {
            uint256 amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), 1e18);
            assertEq(amountOut, 0);
        }

        // Swap in available direction
        {
            uint256 amountIn = 1e18;
            uint256 amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
            assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

            assetTST.mint(address(this), amountIn);

            assetTST.transfer(address(eulerSwap), amountIn);
            eulerSwap.swap(0, amountOut, address(this), "");

            assertEq(assetTST2.balanceOf(address(this)), amountOut);
        }

        // Quote back exact amount in
        {
            uint256 amountIn = assetTST2.balanceOf(address(this));
            uint256 amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);
            assertEq(amountOut, 1e18);
        }

        // Swap back with some extra, no more available
        {
            uint256 amountIn = assetTST2.balanceOf(address(this)) + 1e18;
            uint256 amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);
            assertEq(amountOut, 1e18);
        }

        // Quote exact out amount in, and do swap
        {
            uint256 amountIn;

            vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
            amountIn = periphery.quoteExactOutput(address(eulerSwap), address(assetTST2), address(assetTST), 1e18);

            uint256 amountOut = 1e18 - 1;
            amountIn = periphery.quoteExactOutput(address(eulerSwap), address(assetTST2), address(assetTST), amountOut);

            assertEq(amountIn, assetTST2.balanceOf(address(this)));

            assetTST2.transfer(address(eulerSwap), amountIn);
            eulerSwap.swap(amountOut, 0, address(this), "");
        }

        // Nothing available again (except dust left-over from previous swap)
        {
            uint256 amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), 1e18);
            assertEq(amountOut, 1);
        }
    }
}
