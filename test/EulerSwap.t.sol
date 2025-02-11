// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";

import {Maglev} from "../src/Maglev.sol";

contract EulerSwapTest is MaglevTestBase {
    Maglev public maglev;

    function setUp() public virtual override {
        super.setUp();

        createMaglev(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function createMaglev(
        uint112 debtLimitA,
        uint112 debtLimitB,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) internal {
        vm.prank(creator);
        maglev = new Maglev(
            getMaglevParams(debtLimitA, debtLimitB, fee),
            Maglev.CurveParams({priceX: px, priceY: py, concentrationX: cx, concentrationY: cy})
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);

        vm.prank(anyone);
        maglev.activate();
    }

    function test_different_EVC() public {
        vm.expectRevert(Maglev.DifferentEVC.selector);

        new Maglev(
            Maglev.Params({
                evc: address(makeAddr("RANDOM_EVC")),
                vault0: address(eTST),
                vault1: address(eTST2),
                myAccount: holder,
                debtLimit0: 50e18,
                debtLimit1: 50e18,
                fee: 0
            }),
            Maglev.CurveParams({priceX: 1e18, priceY: 1e18, concentrationX: 4e18, concentrationY: 0.85e18})
        );
    }

    function test_basicSwap_exactIn() public monotonicHolderNAV {
        uint256 amountIn = 1e18;
        uint256 amountOut = periphery.quoteExactInput(address(maglev), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_basicSwap_exactOut() public monotonicHolderNAV {
        uint256 amountOut = 1e18;
        uint256 amountIn = periphery.quoteExactOutput(address(maglev), address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountIn, 1.0025e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(maglev), amountIn);
        maglev.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }

    function test_altPrice() public {
        uint256 price = 0.5e18;
        uint256 px = price;
        uint256 py = 1e18;
        oracle.setPrice(address(eTST), unitOfAccount, 0.5e18);
        oracle.setPrice(address(assetTST), unitOfAccount, 0.5e18);

        int256 origNAV = getHolderNAV();

        createMaglev(50e18, 50e18, 0, px, py, 0.4e18, 0.85e18);

        uint256 amountIn = 1e18;
        uint256 amountOut = periphery.quoteExactInput(address(maglev), address(assetTST), address(assetTST2), amountIn);

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

        uint256 q = periphery.quoteExactInput(address(maglev), address(t1), address(t2), amount);

        t1.transfer(address(maglev), amount);
        if (dir) maglev.swap(0, q, address(this), "");
        else maglev.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);

        t2.transfer(address(maglev), q);
        if (dir) maglev.swap(amount, 0, address(this), "");
        else maglev.swap(0, amount, address(this), "");

        uint256 q2 = periphery.quoteExactInput(address(maglev), address(t1), address(t2), amount);
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

            createMaglev(50e18, 50e18, 0, px, py, cx, cy);
        }

        int256 origNAV = getHolderNAV();

        TestERC20 t1;
        TestERC20 t2;
        if (dir) (t1, t2) = (assetTST, assetTST2);
        else (t1, t2) = (assetTST2, assetTST);

        t1.mint(address(this), amount);
        uint256 q = periphery.quoteExactInput(address(maglev), address(t1), address(t2), amount);

        t1.transfer(address(maglev), amount);
        if (dir) maglev.swap(0, q, address(this), "");
        else maglev.swap(q, 0, address(this), "");
        assertEq(t2.balanceOf(address(this)), q);

        t2.mint(address(this), amount2);
        uint256 q2 = periphery.quoteExactInput(address(maglev), address(t2), address(t1), amount2);

        t2.transfer(address(maglev), amount2);
        if (dir) maglev.swap(q2, 0, address(this), "");
        else maglev.swap(0, q2, address(this), "");
        assertEq(t1.balanceOf(address(this)), q2);

        assertGe(getHolderNAV(), origNAV);
    }

    function test_fuzzAll(uint256 cx, uint256 cy, uint256 fee, uint256[8] calldata amounts, bool[8] calldata dirs)
        public
    {
        cx = bound(cx, 0.01e18, 0.99e18);
        cy = bound(cy, 0.01e18, 0.99e18);
        fee = bound(fee, 0, 0.1e18);

        createMaglev(50e18, 50e18, fee, 1e18, 1e18, cx, cy);

        int256 origNAV = getHolderNAV();

        for (uint256 i = 0; i < 8; i++) {
            uint256 amount = bound(amounts[i], 0.1e18, 5e18);
            bool dir = dirs[i];

            TestERC20 t1;
            TestERC20 t2;
            if (dir) (t1, t2) = (assetTST, assetTST2);
            else (t1, t2) = (assetTST2, assetTST);

            t1.mint(address(this), amount);
            uint256 q = periphery.quoteExactInput(address(maglev), address(t1), address(t2), amount);

            // Try to swap out 1 extra

            t1.transfer(address(maglev), amount);

            {
                uint256 qPlus = q + 1;
                vm.expectRevert();
                if (dir) maglev.swap(0, qPlus, address(this), "");
                else maglev.swap(qPlus, 0, address(this), "");
            }

            // Confirm actual quote works

            uint256 prevBal = t2.balanceOf(address(this));
            if (dir) maglev.swap(0, q, address(this), "");
            else maglev.swap(q, 0, address(this), "");
            assertEq(t2.balanceOf(address(this)), q + prevBal);

            assertGe(getHolderNAV(), origNAV);
        }
    }
}
