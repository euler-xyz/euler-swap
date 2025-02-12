// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";

import {Maglev} from "../src/Maglev.sol";

contract AltDecimals is MaglevTestBase {
    Maglev public maglev;

    function setUp() public virtual override {
        super.setUp();
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
    }

    function test_alt_decimals_6_18_in() public {
        createMaglev(50e6, 50e18, 0, 1e18, 1e6, 0.9e18, 0.9e18);
        skimAll(maglev, true);

        uint256 amount = 1e6;
        uint256 q = periphery.quoteExactInput(address(maglev), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e18, 0.01e18);

        assetTST.mint(address(this), amount);
        assetTST.transfer(address(maglev), amount);

        {
            uint256 qPlus = q + 1;
            vm.expectRevert();
            maglev.swap(0, qPlus, address(this), "");
        }

        maglev.swap(0, q, address(this), "");
    }

    function test_alt_decimals_6_18_out() public {
        createMaglev(50e6, 50e18, 0, 1e18, 1e6, 0.9e18, 0.9e18);
        skimAll(maglev, true);

        uint256 amount = 1e18;
        uint256 q = periphery.quoteExactOutput(address(maglev), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e6, 0.01e6);

        assetTST.mint(address(this), q);
        assetTST.transfer(address(maglev), q);

        {
            uint256 amountPlus = amount + 0.0000001e18;
            vm.expectRevert();
            maglev.swap(0, amountPlus, address(this), "");
        }

        maglev.swap(0, amount, address(this), "");
    }

    function test_alt_decimals_18_6_in() public {
        createMaglev(50e18, 50e6, 0, 1e6, 1e18, 0.9e18, 0.9e18);
        skimAll(maglev, true);

        uint256 amount = 1e18;
        uint256 q = periphery.quoteExactInput(address(maglev), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e6, 0.01e6);

        assetTST.mint(address(this), amount);
        assetTST.transfer(address(maglev), amount);

        {
            uint256 qPlus = q + 1;
            vm.expectRevert();
            maglev.swap(0, qPlus, address(this), "");
        }

        maglev.swap(0, q, address(this), "");
    }

    function test_alt_decimals_18_6_out() public {
        createMaglev(50e18, 50e6, 0, 1e6, 1e18, 0.9e18, 0.9e18);
        skimAll(maglev, false);

        uint256 amount = 1e6;
        uint256 q = periphery.quoteExactOutput(address(maglev), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e18, 0.01e18);

        assetTST.mint(address(this), q);
        assetTST.transfer(address(maglev), q);

        {
            uint256 amountPlus = amount + 1;
            vm.expectRevert();
            maglev.swap(0, amountPlus, address(this), "");
        }

        maglev.swap(0, amount, address(this), "");
    }
}
