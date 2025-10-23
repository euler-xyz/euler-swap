// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EVaultTestBase, TestERC20, IRMTestDefault} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEulerSwap, EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapProtocolFeeConfig} from "../src/EulerSwapProtocolFeeConfig.sol";
import {EulerSwapManagement} from "../src/EulerSwapManagement.sol";
import {EulerSwapRegistry} from "../src/EulerSwapRegistry.sol";
import {EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {PerspectiveMock} from "./utils/PerspectiveMock.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {MetaProxyDeployer} from "../src/utils/MetaProxyDeployer.sol";

contract EulerSwapTestBase is EVaultTestBase {
    uint256 public constant MAX_QUOTE_ERROR = 1;

    address public depositor = makeAddr("depositor");
    address public holder = makeAddr("holder");
    address public recipient = makeAddr("recipient");
    address public anyone = makeAddr("anyone");
    address public curator = makeAddr("curator");
    address public protocolFeeAdmin = makeAddr("protocolFeeAdmin");

    TestERC20 assetTST3;
    IEVault public eTST3;

    EulerSwapProtocolFeeConfig public protocolFeeConfig;
    address public eulerSwapManagementImpl;
    address public eulerSwapImpl;
    PerspectiveMock public validVaultPerspective;
    EulerSwapFactory public eulerSwapFactory;
    EulerSwapRegistry public eulerSwapRegistry;
    EulerSwapPeriphery public periphery;

    uint256 currSalt = 0;
    address installedOperator;
    bool expectInsufficientValidityBondRevert = false;
    bool expectAccountLiquidityRevert = false;

    error E_AccountLiquidity();

    modifier monotonicHolderNAV() {
        int256 orig = getHolderNAV();
        _;
        assertGe(getHolderNAV(), orig);
    }

    function deployEulerSwap(address poolManager_) public {
        validVaultPerspective = new PerspectiveMock();
        protocolFeeConfig = new EulerSwapProtocolFeeConfig(address(evc), protocolFeeAdmin);
        eulerSwapManagementImpl = address(new EulerSwapManagement(address(evc)));
        eulerSwapImpl =
            address(new EulerSwap(address(evc), address(protocolFeeConfig), poolManager_, eulerSwapManagementImpl));
        eulerSwapFactory = new EulerSwapFactory(address(evc), eulerSwapImpl);
        eulerSwapRegistry =
            new EulerSwapRegistry(address(evc), address(eulerSwapFactory), address(validVaultPerspective), curator);
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

    function createEulerSwap(uint112 reserve0, uint112 reserve1, uint64 fee, uint80 px, uint80 py, uint64 cx, uint64 cy)
        internal
        returns (EulerSwap)
    {
        (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
            getEulerSwapParams(reserve0, reserve1, px, py, cx, cy, fee, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: reserve0, reserve1: reserve1});

        return createEulerSwapFull(sParams, dParams, initialState);
    }

    function createEulerSwapFull(
        IEulerSwap.StaticParams memory sParams,
        IEulerSwap.DynamicParams memory dParams,
        IEulerSwap.InitialState memory initialState
    ) internal returns (EulerSwap) {
        removeInstalledOperator();

        bytes32 salt = bytes32(currSalt++);

        address predictedAddr = eulerSwapFactory.computePoolAddress(sParams, salt);

        vm.prank(holder);
        evc.setAccountOperator(sParams.eulerAccount, predictedAddr, true);
        installedOperator = predictedAddr;

        uint256 ethBalance = holder.balance;

        vm.prank(holder);
        if (expectAccountLiquidityRevert) vm.expectRevert(E_AccountLiquidity.selector);
        bytes memory result = IEVC(evc).call(
            address(eulerSwapFactory),
            sParams.eulerAccount,
            0,
            abi.encodeCall(EulerSwapFactory.deployPool, (sParams, dParams, initialState, salt))
        );
        if (expectAccountLiquidityRevert) return EulerSwap(address(0)); // Just to return to test
        EulerSwap eulerSwap = EulerSwap(abi.decode(result, (address)));

        vm.prank(holder);
        if (expectInsufficientValidityBondRevert) vm.expectRevert(EulerSwapRegistry.InsufficientValidityBond.selector);
        IEVC(evc).call{value: ethBalance}(
            address(eulerSwapRegistry),
            sParams.eulerAccount,
            ethBalance,
            abi.encodeCall(EulerSwapRegistry.registerPool, (address(eulerSwap)))
        );

        return eulerSwap;
    }

    function createEulerSwapHookFull(
        IEulerSwap.StaticParams memory sParams,
        IEulerSwap.DynamicParams memory dParams,
        IEulerSwap.InitialState memory initialState
    ) internal returns (EulerSwap) {
        removeInstalledOperator();

        bytes memory creationCode = eulerSwapFactory.creationCode(sParams);
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
        EulerSwap eulerSwap = EulerSwap(eulerSwapFactory.deployPool(sParams, dParams, initialState, salt));

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
        uint80 px,
        uint80 py,
        uint64 cx,
        uint64 cy,
        uint64 fee,
        address feeRecipient
    ) internal view returns (EulerSwap.StaticParams memory sParams, EulerSwap.DynamicParams memory dParams) {
        sParams = IEulerSwap.StaticParams({
            supplyVault0: address(eTST),
            borrowVault0: address(eTST),
            supplyVault1: address(eTST2),
            borrowVault1: address(eTST2),
            eulerAccount: holder,
            feeRecipient: feeRecipient
        });

        dParams = IEulerSwap.DynamicParams({
            equilibriumReserve0: reserve0,
            equilibriumReserve1: reserve1,
            minReserve0: 0,
            minReserve1: 0,
            priceX: px,
            priceY: py,
            concentrationX: cx,
            concentrationY: cy,
            fee0: fee,
            fee1: fee,
            expiration: 0,
            swapHookedOperations: 0,
            swapHook: address(0)
        });
    }

    struct PoolConfig {
        EulerSwap.StaticParams sParams;
        EulerSwap.DynamicParams dParams;
        EulerSwap.InitialState initialState;
    }

    function getPoolConfig(EulerSwap eulerSwap) internal view returns (PoolConfig memory pc) {
        pc.sParams = eulerSwap.getStaticParams();
        pc.dParams = eulerSwap.getDynamicParams();
        (pc.initialState.reserve0, pc.initialState.reserve1,) = eulerSwap.getReserves();
    }

    function reconfigurePool(EulerSwap eulerSwap, PoolConfig memory pc) internal {
        vm.prank(pc.sParams.eulerAccount);
        eulerSwap.reconfigure(pc.dParams, pc.initialState);
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

    function verifyInLimitSwappable(EulerSwap es, TestERC20 t1, TestERC20 t2) internal {
        uint256 snapshot = vm.snapshotState();

        (uint256 inLimit,) = periphery.getLimits(address(es), address(t1), address(t2));

        uint256 amountOut = periphery.quoteExactInput(address(es), address(t1), address(t2), inLimit);

        t1.mint(address(this), inLimit);
        t1.transfer(address(es), inLimit);

        if (t1 == assetTST) es.swap(0, amountOut, address(this), "");
        else es.swap(amountOut, 0, address(this), "");

        if (inLimit > 0) {
            inLimit = inLimit * 1.01e18 / 1e18;

            vm.expectRevert();
            periphery.quoteExactInput(address(es), address(t1), address(t2), inLimit);
        }

        vm.revertToState(snapshot);
    }

    function verifyOutLimitSwappable(EulerSwap es, TestERC20 t1, TestERC20 t2) internal {
        uint256 snapshot = vm.snapshotState();

        (, uint256 outLimit) = periphery.getLimits(address(es), address(t1), address(t2));

        uint256 amountIn = periphery.quoteExactOutput(address(es), address(t1), address(t2), outLimit);

        t1.mint(address(this), amountIn);
        t1.transfer(address(es), amountIn);

        if (t1 == assetTST) es.swap(0, outLimit, address(this), "");
        else es.swap(outLimit, 0, address(this), "");

        if (outLimit > 0) {
            outLimit = outLimit * 1.01e18 / 1e18;

            vm.expectRevert();
            periphery.quoteExactOutput(address(es), address(t1), address(t2), outLimit);
        }

        vm.revertToState(snapshot);
    }
}
