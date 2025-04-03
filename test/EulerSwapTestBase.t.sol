// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EVaultTestBase, TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap, IEVC, EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";

contract EulerSwapTestBase is EVaultTestBase {
    address public depositor = makeAddr("depositor");
    address public creator = makeAddr("creator");
    address public holder = makeAddr("holder");
    address public recipient = makeAddr("recipient");
    address public anyone = makeAddr("anyone");

    EulerSwapPeriphery public periphery;

    modifier monotonicHolderNAV() {
        int256 orig = getHolderNAV();
        _;
        assertGe(getHolderNAV(), orig);
    }

    function setUp() public virtual override {
        super.setUp();

        periphery = new EulerSwapPeriphery();

        // Vault config

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);
        eTST2.setLTV(address(eTST), 0.9e4, 0.9e4, 0);

        // Pricing

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);

        oracle.setPrice(address(assetTST), address(assetTST2), 1e18);
        oracle.setPrice(address(assetTST2), address(assetTST), 1e18);

        // Funding

        mintAndDeposit(depositor, eTST, 100e18);
        mintAndDeposit(depositor, eTST2, 100e18);

        mintAndDeposit(holder, eTST, 10e18);
        mintAndDeposit(holder, eTST2, 10e18);
    }

    function skimAll(EulerSwap ml, bool order) public {
        if (order) {
            runSkimAll(ml, true);
            runSkimAll(ml, false);
        } else {
            runSkimAll(ml, false);
            runSkimAll(ml, true);
        }
    }

    function getHolderNAV() internal view returns (int256) {
        uint256 balance0 = eTST.convertToAssets(eTST.balanceOf(holder));
        uint256 debt0 = eTST.debtOf(holder);
        uint256 balance1 = eTST2.convertToAssets(eTST2.balanceOf(holder));
        uint256 debt1 = eTST2.debtOf(holder);

        uint256 balValue = oracle.getQuote(balance0, address(assetTST), unitOfAccount)
            + oracle.getQuote(balance1, address(assetTST2), unitOfAccount);
        uint256 debtValue = oracle.getQuote(debt0, address(assetTST), unitOfAccount)
            + oracle.getQuote(debt1, address(assetTST2), unitOfAccount);

        return int256(balValue) - int256(debtValue);
    }

    function createEulerSwap(
        uint112 debtLimitA,
        uint112 debtLimitB,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) internal returns (EulerSwap) {
        vm.prank(creator);
        EulerSwap eulerSwap = new EulerSwap(
            getEulerSwapParams(debtLimitA, debtLimitB, fee),
            IEulerSwap.CurveParams({priceX: px, priceY: py, concentrationX: cx, concentrationY: cy})
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), true);

        return eulerSwap;
    }

    function mintAndDeposit(address who, IEVault vault, uint256 amount) internal {
        TestERC20 tok = TestERC20(vault.asset());
        tok.mint(who, amount);

        vm.prank(who);
        tok.approve(address(vault), type(uint256).max);

        vm.prank(who);
        vault.deposit(amount, who);
    }

    function runSkimAll(EulerSwap ml, bool dir) internal returns (uint256) {
        uint256 skimmed = 0;
        uint256 val = 1;

        // Phase 1: Keep doubling skim amount until it fails

        while (true) {
            (uint256 amount0, uint256 amount1) = dir ? (val, uint256(0)) : (uint256(0), val);

            try ml.swap(amount0, amount1, address(0xDEAD), "") {
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

            try ml.swap(amount0, amount1, address(0xDEAD), "") {
                skimmed += val;
            } catch {
                if (val == 1) break;
            }
        }

        return skimmed;
    }

    function getEulerSwapParams(uint112 reserve0, uint112 reserve1, uint256 fee)
        internal
        view
        returns (EulerSwap.Params memory)
    {
        return IEulerSwap.Params({
            vault0: address(eTST),
            vault1: address(eTST2),
            eulerAccount: holder,
            protocolFeeRecipient: address(0),
            equilibriumReserve0: reserve0,
            equilibriumReserve1: reserve1,
            currReserve0: reserve0,
            currReserve1: reserve1,
            fee: fee,
            protocolFee: 0
        });
    }

    function logState(address ml) internal view {
        (uint112 reserve0, uint112 reserve1,) = EulerSwap(ml).getReserves();

        console.log("--------------------");
        console.log("Account States:");
        console.log("HOLDER");
        console.log("  eTST Vault assets:  ", eTST.convertToAssets(eTST.balanceOf(holder)));
        console.log("  eTST Vault debt:    ", eTST.debtOf(holder));
        console.log("  eTST2 Vault assets: ", eTST2.convertToAssets(eTST2.balanceOf(holder)));
        console.log("  eTST2 Vault debt:   ", eTST2.debtOf(holder));
        console.log("  reserve0:           ", reserve0);
        console.log("  reserve1:           ", reserve1);
    }
}
