// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EVaultTestBase, TestERC20, IRMTestDefault} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap, IEVC, EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {MetaProxyDeployer} from "../src/utils/MetaProxyDeployer.sol";

contract EulerSwapTestBase is EVaultTestBase {
    uint256 public constant MAX_QUOTE_ERROR = 2;

    address public depositor = makeAddr("depositor");
    address public holder = makeAddr("holder");
    address public recipient = makeAddr("recipient");
    address public anyone = makeAddr("anyone");

    TestERC20 assetTST3;
    IEVault public eTST3;

    address public eulerSwapImpl;
    EulerSwapFactory public eulerSwapFactory;
    EulerSwapPeriphery public periphery;

    uint256 currSalt = 0;
    address installedOperator;

    modifier monotonicHolderNAV() {
        int256 orig = getHolderNAV();
        _;
        assertGe(getHolderNAV(), orig);
    }

    function deployEulerSwap(address poolManager_) public {
        eulerSwapImpl = address(new EulerSwap(address(evc), poolManager_));
        eulerSwapFactory = new EulerSwapFactory(address(evc), address(factory), eulerSwapImpl, address(this));
        periphery = new EulerSwapPeriphery();
    }

    function removeInstalledOperator() public {
        if (installedOperator == address(0)) return;

        vm.prank(holder);
        evc.setAccountOperator(holder, installedOperator, false);

        installedOperator = address(0);
    }

    function setUp() public virtual override {
        super.setUp();

        deployEulerSwap(address(0)); // Default is no poolManager

        // deploy more vaults
        assetTST3 = new TestERC20("Test Token 3", "TST3", 18, false);
        eTST3 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST3), address(oracle), unitOfAccount))
        );
        eTST3.setHookConfig(address(0), 0);
        eTST3.setInterestRateModel(address(new IRMTestDefault()));
        eTST3.setMaxLiquidationDiscount(0.2e4);
        eTST3.setFeeReceiver(feeReceiver);

        // Vault config

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);
        eTST2.setLTV(address(eTST), 0.9e4, 0.9e4, 0);
        eTST.setLTV(address(eTST3), 0.9e4, 0.9e4, 0);

        // Pricing

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST3), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST3), unitOfAccount, 1e18);

        oracle.setPrice(address(assetTST), address(assetTST2), 1e18);
        oracle.setPrice(address(assetTST2), address(assetTST), 1e18);
        oracle.setPrice(address(assetTST), address(assetTST3), 1e18);
        oracle.setPrice(address(assetTST3), address(assetTST), 1e18);

        // Funding

        mintAndDeposit(depositor, eTST, 100e18);
        mintAndDeposit(depositor, eTST2, 100e18);
        mintAndDeposit(depositor, eTST3, 100e18);

        mintAndDeposit(holder, eTST, 10e18);
        mintAndDeposit(holder, eTST2, 10e18);
        mintAndDeposit(holder, eTST3, 10e18);
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
        uint112 reserve0,
        uint112 reserve1,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) internal returns (EulerSwap) {
        return createEulerSwapFull(reserve0, reserve1, fee, px, py, cx, cy, 0, address(0));
    }

    function createEulerSwapFull(
        uint112 reserve0,
        uint112 reserve1,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy,
        uint256 protocolFee,
        address protocolFeeRecipient
    ) internal returns (EulerSwap) {
        removeInstalledOperator();

        IEulerSwap.Params memory params =
            getEulerSwapParams(reserve0, reserve1, px, py, cx, cy, fee, protocolFee, protocolFeeRecipient);
        IEulerSwap.InitialState memory initialState =
            IEulerSwap.InitialState({currReserve0: reserve0, currReserve1: reserve1});

        bytes32 salt = bytes32(currSalt++);

        address predictedAddr = eulerSwapFactory.computePoolAddress(params, salt);

        vm.prank(holder);
        evc.setAccountOperator(holder, predictedAddr, true);
        installedOperator = predictedAddr;

        vm.prank(holder);
        EulerSwap eulerSwap = EulerSwap(eulerSwapFactory.deployPool(params, initialState, salt));

        return eulerSwap;
    }

    function createEulerSwapHook(
        uint112 reserve0,
        uint112 reserve1,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) internal returns (EulerSwap) {
        return createEulerSwapHookFull(reserve0, reserve1, fee, px, py, cx, cy, 0, address(0));
    }

    function createEulerSwapHookFull(
        uint112 reserve0,
        uint112 reserve1,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy,
        uint256 protocolFee,
        address protocolFeeRecipient
    ) internal returns (EulerSwap) {
        removeInstalledOperator();

        IEulerSwap.Params memory params =
            getEulerSwapParams(reserve0, reserve1, px, py, cx, cy, fee, protocolFee, protocolFeeRecipient);
        IEulerSwap.InitialState memory initialState =
            IEulerSwap.InitialState({currReserve0: reserve0, currReserve1: reserve1});

        bytes memory creationCode = MetaProxyDeployer.creationCodeMetaProxy(eulerSwapImpl, abi.encode(params));
        (address predictedAddr, bytes32 salt) = HookMiner.find(
            address(eulerSwapFactory),
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            ),
            creationCode
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, predictedAddr, true);
        installedOperator = predictedAddr;

        vm.prank(holder);
        EulerSwap eulerSwap = EulerSwap(eulerSwapFactory.deployPool(params, initialState, salt));

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

    function getEulerSwapParams(
        uint112 reserve0,
        uint112 reserve1,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy,
        uint256 fee,
        uint256 protocolFee,
        address protocolFeeRecipient
    ) internal view returns (EulerSwap.Params memory) {
        return IEulerSwap.Params({
            vault0: address(eTST),
            vault1: address(eTST2),
            eulerAccount: holder,
            equilibriumReserve0: reserve0,
            equilibriumReserve1: reserve1,
            priceX: px,
            priceY: py,
            concentrationX: cx,
            concentrationY: cy,
            fee: fee,
            protocolFee: protocolFee,
            protocolFeeRecipient: protocolFeeRecipient
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
