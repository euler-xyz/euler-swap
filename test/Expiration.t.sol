// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {QuoteLib} from "../src/libraries/QuoteLib.sol";

contract Expiration is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

        PoolConfig memory pc = getPoolConfig(eulerSwap);
        pc.dParams.expiration = uint40(block.timestamp + 1000);
        reconfigurePool(eulerSwap, pc);
    }

    function test_unexpired() public {
        // Quoting

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        // Limits

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
        assertTrue(inLimit > 0);
        assertApproxEqAbs(outLimit, 60e18, 0.001e18);

        // Swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_expired() public {
        skip(2000);

        // Quoting

        uint256 amountIn = 1e18;
        vm.expectRevert(QuoteLib.Expired.selector);
        periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        // Limits

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
        assertEq(inLimit, 0);
        assertEq(outLimit, 0);

        // Swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        vm.expectRevert(QuoteLib.Expired.selector);
        eulerSwap.swap(0, 1, address(this), "");
    }
}
