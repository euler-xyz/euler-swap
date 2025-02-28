// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {console, IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract ReinstallTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_basicSwap_exactIn() public monotonicHolderNAV {
        console.log("MP 1",marginalPrice());

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        console.log("MP 2",marginalPrice());

        eulerSwap = createEulerSwap(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

        console.log("MP 3",marginalPrice());
    }

    function marginalPrice() internal returns (uint256) {
        uint256 scale = 1e6;
        uint256 out = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), scale);
        return scale * 1e18 / out;
    }
}
