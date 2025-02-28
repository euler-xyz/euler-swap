// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract EulerSwapTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_basicSwap_exactIn() public monotonicHolderNAV {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_basicSwap_exactOut() public monotonicHolderNAV {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountIn, 1.0025e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_altPrice() public {
        uint256 price = 0.5e18;
        uint256 px = price;
        uint256 py = 1e18;
        oracle.setPrice(address(eTST), unitOfAccount, 0.5e18);
        oracle.setPrice(address(assetTST), unitOfAccount, 0.5e18);

        int256 origNAV = getHolderNAV();

        eulerSwap = createEulerSwap(50e18, 50e18, 0, px, py, 0.4e18, 0.85e18);

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");
        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        assertGe(getHolderNAV(), origNAV);
    }

    function test_pathIndependent(uint256 amount, bool dir) public monotonicHolderNAV {
        amount = bound(amount, 0.1e18, 25e18);

        TestERC20 t1;
        TestERC20 t2;
        if (dir) (t1, t2) = (assetTST, assetTST2);
        else (t1, t2) = (assetTST2, assetTST);

        t1.mint(address(this), amount);

        uint256 q = periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amount);

        t1.transfer(address(eulerSwap), amount);
        if (dir) eulerSwap.swap(0, q, address(this), "");
        else eulerSwap.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);

        t2.transfer(address(eulerSwap), q);
        if (dir) eulerSwap.swap(amount, 0, address(this), "");
        else eulerSwap.swap(0, amount, address(this), "");

        uint256 q2 = periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amount);
        assertEq(q, q2);
    }

    function test_fuzzParams(uint256 amount, uint256 amount2, uint256 price, uint256 cx, uint256 cy, bool dir) public {
        amount = bound(amount, 0.1e18, 25e18);
        amount2 = bound(amount2, 0.1e18, 25e18);
        price = bound(price, 0.1e18, 10e18);
        cx = bound(cx, 0.01e18, 0.99e18);
        cy = bound(cy, 0.01e18, 0.99e18);

        {
            uint256 px = price;
            uint256 py = 1e18;
            oracle.setPrice(address(eTST), unitOfAccount, price);
            oracle.setPrice(address(assetTST), unitOfAccount, price);

            eulerSwap = createEulerSwap(50e18, 50e18, 0, px, py, cx, cy);
        }

        int256 origNAV = getHolderNAV();

        TestERC20 t1;
        TestERC20 t2;
        if (dir) (t1, t2) = (assetTST, assetTST2);
        else (t1, t2) = (assetTST2, assetTST);

        t1.mint(address(this), amount);
        uint256 q = periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amount);

        t1.transfer(address(eulerSwap), amount);
        if (dir) eulerSwap.swap(0, q, address(this), "");
        else eulerSwap.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);

        t2.mint(address(this), amount2);
        uint256 q2 = periphery.quoteExactInput(address(eulerSwap), address(t2), address(t1), amount2);

        t2.transfer(address(eulerSwap), amount2);
        if (dir) eulerSwap.swap(q2, 0, address(this), "");
        else eulerSwap.swap(0, q2, address(this), "");
        assertEq(t1.balanceOf(address(this)), q2);

        assertGe(getHolderNAV(), origNAV);
    }

    function test_fuzzAll(uint256 cx, uint256 cy, uint256 fee, uint256[8] calldata amounts, bool[8] calldata dirs)
        public
    {
        cx = bound(cx, 0.01e18, 0.99e18);
        cy = bound(cy, 0.01e18, 0.99e18);
        fee = bound(fee, 0, 0.1e18);

        eulerSwap = createEulerSwap(50e18, 50e18, fee, 1e18, 1e18, cx, cy);

        int256 origNAV = getHolderNAV();

        for (uint256 i = 0; i < 8; i++) {
            uint256 amount = bound(amounts[i], 0.1e18, 5e18);
            bool dir = dirs[i];

            TestERC20 t1;
            TestERC20 t2;
            if (dir) (t1, t2) = (assetTST, assetTST2);
            else (t1, t2) = (assetTST2, assetTST);

            t1.mint(address(this), amount);
            uint256 q = periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amount);

            // Try to swap out 1 extra

            t1.transfer(address(eulerSwap), amount);

            {
                uint256 qPlus = q + 1;
                vm.expectRevert();
                if (dir) eulerSwap.swap(0, qPlus, address(this), "");
                else eulerSwap.swap(qPlus, 0, address(this), "");
            }

            // Confirm actual quote works

            uint256 prevBal = t2.balanceOf(address(this));
            if (dir) eulerSwap.swap(0, q, address(this), "");
            else eulerSwap.swap(q, 0, address(this), "");
            assertEq(t2.balanceOf(address(this)), q + prevBal);

            assertGe(getHolderNAV(), origNAV);
        }
    }

    /*
    // Make `f()` function public to run this test
    function test_fFuncOverflow(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal view {
        x0 = bound(x0, 1, type(uint112).max);
        y0 = bound(y0, 0, type(uint112).max);
        xt = bound(xt, 1 + x0 / 1e3, x0); // thousand-fold price movement
        px = bound(px, 1, 1e36);
        py = bound(py, 1, 1e36);
        c = bound(c, 1, 1e18);

        eulerSwap.f(xt, px, py, x0, y0, c);
    }
    */
}
