// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";

import {MaglevEulerSwap as Maglev} from "../src/MaglevEulerSwap.sol";

contract EulerSwapTest is MaglevTestBase {
    Maglev public maglev;

    uint256 minFee = 0.0000000000001e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(owner);
        maglev = new Maglev(
            _getMaglevBaseParams(), Maglev.EulerSwapParams({px: 1e18, py: 1e18, cx: 0.4e18, cy: 0.85e18, fee: minFee})
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);

        vm.prank(owner);
        maglev.configure();

        vm.prank(owner);
        maglev.setDebtLimit(50e18, 50e18);

        assertTrue(maglev.asset0() < maglev.asset1());
    }

    function test_basicSwap_exactIn() public monotonicHolderNAV {
        uint256 amountIn = 1e18;
        uint256 amountOut = maglev.quoteExactInput(address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_basicSwap_exactOut() public monotonicHolderNAV {
        uint256 amountOut = 1e18;
        uint256 amountIn = maglev.quoteExactOutput(address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountIn, 1.0025e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_price() public {
        uint256 price = 0.5e18;
        uint256 px = price;
        uint256 py = 1e18;
        oracle.setPrice(address(eTST), unitOfAccount, 0.5e18);
        oracle.setPrice(address(assetTST), unitOfAccount, 0.5e18);

        int256 origNAV = getHolderNAV();

        vm.prank(owner);
        maglev.setEulerSwapParams(Maglev.EulerSwapParams({px: px, py: py, cx: 0.4e18, cy: 0.85e18, fee: minFee}));

        uint256 amountIn = 1e18;
        uint256 amountOut = maglev.quoteExactInput(address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");
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

        uint256 q = maglev.quoteExactInput(address(t1), address(t2), amount);

        t1.transfer(address(maglev), amount);
        if (dir) maglev.swap(0, q, address(this), "");
        else maglev.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);

        t2.transfer(address(maglev), q);
        if (dir) maglev.swap(amount - 2, 0, address(this), ""); // - 2 due to rounding

        else maglev.swap(0, amount - 2, address(this), "");

        uint256 q2 = maglev.quoteExactInput(address(t1), address(t2), amount);
        assertApproxEqAbs(q, q2, 0.00000001e18);
    }

    function test_fuzzParams(uint256 amount, uint256 amount2, uint256 price, uint256 cx, uint256 cy, bool dir) public {
        amount = bound(amount, 0.1e18, 25e18);
        amount2 = bound(amount2, 0.1e18, 25e18);
        price = bound(price, 0.1e18, 10e18);
        cx = bound(cx, 0.01e18, 0.99e18);
        cy = bound(cy, 0.01e18, 0.99e18);

        uint256 px = price;
        uint256 py = 1e18;
        oracle.setPrice(address(eTST), unitOfAccount, price);
        oracle.setPrice(address(assetTST), unitOfAccount, price);

        vm.prank(owner);
        maglev.setEulerSwapParams(Maglev.EulerSwapParams({px: px, py: py, cx: cx, cy: cy, fee: minFee}));

        int256 origNAV = getHolderNAV();

        TestERC20 t1;
        TestERC20 t2;
        if (dir) (t1, t2) = (assetTST, assetTST2);
        else (t1, t2) = (assetTST2, assetTST);

        t1.mint(address(this), amount);
        uint256 q = maglev.quoteExactInput(address(t1), address(t2), amount);

        t1.transfer(address(maglev), amount);
        if (dir) maglev.swap(0, q, address(this), "");
        else maglev.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);

        t2.mint(address(this), amount2);
        uint256 q2 = maglev.quoteExactInput(address(t2), address(t1), amount2);

        t2.transfer(address(maglev), amount2);
        if (dir) maglev.swap(q2, 0, address(this), "");
        else maglev.swap(0, q2, address(this), "");
        assertEq(t1.balanceOf(address(this)), q2);

        assertGe(getHolderNAV(), origNAV);
    }

    function test_roundingFailure() public {
        vm.skip(true);

        vm.prank(owner);
        maglev.setEulerSwapParams(Maglev.EulerSwapParams({px: 1e18, py: 1e18, cx: 0.4e18, cy: 0.85e18, fee: 0}));

        uint256 amountIn = 1.4e18;
        uint256 amountOut = maglev.quoteExactInput(address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");
        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }
}
