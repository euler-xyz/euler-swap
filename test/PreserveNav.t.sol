// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";

import {Maglev} from "../src/Maglev.sol";

contract PreserveNav is MaglevTestBase {
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

        vm.prank(anyone);
        maglev.activate();
    }

    function test_preserve_nav(
        uint256 cx,
        uint256 cy,
        uint256 fee,
        bool preSkimDir,
        bool dir1,
        uint256 amount1,
        bool dir2,
        uint256 amount2
    ) public {
        cx = bound(cx, 0.1e18, 0.99e18);
        cy = bound(cy, 0.1e18, 0.99e18);
        fee = bound(fee, 0, 0.2e18);
        amount1 = bound(amount1, 0.00001e18, 25e18);
        amount2 = bound(amount2, 0.00001e18, 25e18);

        if (fee < 0.1e18) fee = 0; // half of the time use fee 0

        else fee -= 0.1e18;

        createMaglev(50e18, 50e18, fee, 1e18, 1e18, cx, cy);

        skimAll(preSkimDir);
        int256 nav1 = getHolderNAV();

        {
            TestERC20 t1;
            TestERC20 t2;
            if (dir1) (t1, t2) = (assetTST, assetTST2);
            else (t1, t2) = (assetTST2, assetTST);

            uint256 q = periphery.quoteExactInput(address(maglev), address(t1), address(t2), amount1);

            t1.mint(address(this), amount1);
            t1.transfer(address(maglev), amount1);

            {
                uint256 qPlus = q + 1;
                vm.expectRevert();
                if (dir1) maglev.swap(0, qPlus, address(this), "");
                else maglev.swap(qPlus, 0, address(this), "");
            }

            if (dir1) maglev.swap(0, q, address(this), "");
            else maglev.swap(q, 0, address(this), "");
        }

        assertGe(getHolderNAV(), nav1);

        {
            TestERC20 t1;
            TestERC20 t2;
            if (dir2) (t1, t2) = (assetTST, assetTST2);
            else (t1, t2) = (assetTST2, assetTST);

            uint256 q = periphery.quoteExactInput(address(maglev), address(t1), address(t2), amount2);

            t1.mint(address(this), amount2);
            t1.transfer(address(maglev), amount2);

            {
                uint256 qPlus = q + 1;
                vm.expectRevert();
                if (dir2) maglev.swap(0, qPlus, address(this), "");
                else maglev.swap(qPlus, 0, address(this), "");
            }

            if (dir2) maglev.swap(0, q, address(this), "");
            else maglev.swap(q, 0, address(this), "");
        }

        assertGe(getHolderNAV(), nav1);
    }

    function _skimAll(bool dir) public returns (uint256) {
        uint256 skimmed = 0;
        uint256 val = 1;

        // Phase 1: Keep doubling skim amount until it fails

        while (true) {
            (uint256 amount0, uint256 amount1) = dir ? (val, uint256(0)) : (uint256(0), val);

            try maglev.swap(amount0, amount1, address(0xDEAD), "") {
                skimmed += val;
                val *= 2;
            } catch {
                break;
            }
        }

        // Phase 2: Keep halving skim amount until 1 wei skim fails

        while (true) {
            if (val > 1) val /= 2;

            (uint256 amount0, uint256 amount1) = dir ? (val, uint256(0)) : (uint256(0), val);

            try maglev.swap(amount0, amount1, address(0xDEAD), "") {
                skimmed += val;
            } catch {
                if (val == 1) break;
            }
        }

        return skimmed;
    }

    function skimAll(bool order) public {
        if (order) {
            _skimAll(true);
            _skimAll(false);
        } else {
            _skimAll(false);
            _skimAll(true);
        }
    }
}
