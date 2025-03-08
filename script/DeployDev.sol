// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

// System

import {Script, console} from "forge-std/Script.sol";

// Deploy base

import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";

import {EVault} from "evk/EVault/EVault.sol";
import {ProtocolConfig} from "evk/ProtocolConfig/ProtocolConfig.sol";

import {Dispatch} from "evk/EVault/Dispatch.sol";

import {Initialize} from "evk/EVault/modules/Initialize.sol";
import {Token} from "evk/EVault/modules/Token.sol";
import {Vault} from "evk/EVault/modules/Vault.sol";
import {Borrowing} from "evk/EVault/modules/Borrowing.sol";
import {Liquidation} from "evk/EVault/modules/Liquidation.sol";
import {BalanceForwarder} from "evk/EVault/modules/BalanceForwarder.sol";
import {Governance} from "evk/EVault/modules/Governance.sol";
import {RiskManager} from "evk/EVault/modules/RiskManager.sol";

import {IEVault, IERC20} from "evk/EVault/IEVault.sol";
import {TypesLib} from "evk/EVault/shared/types/Types.sol";
import {Base} from "evk/EVault/shared/Base.sol";

import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

import {TestERC20} from "evk-test/mocks/TestERC20.sol";
import {MockBalanceTracker} from "evk-test/mocks/MockBalanceTracker.sol";
import {MockPriceOracle} from "evk-test/mocks/MockPriceOracle.sol";
import {IRMTestDefault} from "evk-test/mocks/IRMTestDefault.sol";
import {IHookTarget} from "evk/interfaces/IHookTarget.sol";
import {SequenceRegistry} from "evk/SequenceRegistry/SequenceRegistry.sol";

// Euler swap

import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap, IEVC, EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapHub} from "../src/EulerSwapHub.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";

struct Asset {
    string symbol;
    address asset;
    address vault;
}

contract DeployDev is Script {
    //////// Users

    uint256 user0PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 user1PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 user2PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 user3PK = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    address user0 = vm.addr(user0PK);
    address user1 = vm.addr(user1PK);
    address user2 = vm.addr(user2PK);
    address user3 = vm.addr(user3PK);

    //////// Main system

    EthereumVaultConnector public evc;
    address admin;
    address feeReceiver;
    address protocolFeeReceiver;
    ProtocolConfig protocolConfig;
    address balanceTracker;
    MockPriceOracle oracle;
    address unitOfAccount;
    address permit2;
    address sequenceRegistry;
    GenericFactory public factory;

    Base.Integrations integrations;
    Dispatch.DeployedModules modules;

    address initializeModule;
    address tokenModule;
    address vaultModule;
    address borrowingModule;
    address liquidationModule;
    address riskManagerModule;
    address balanceForwarderModule;
    address governanceModule;

    //////// Tokens

    Asset[] assets;

    //////// EulerSwap

    EulerSwapHub hub;
    EulerSwapPeriphery periphery;

    function run() public {
        vm.startBroadcast(user3PK);

        deployMainSystem();
        deployAssets();
        deployEulerSwap();

        vm.stopBroadcast();

        setupUsers();
    }

    function deployMainSystem() internal {
        admin = makeAddr("admin");
        feeReceiver = makeAddr("feeReceiver");
        protocolFeeReceiver = makeAddr("protocolFeeReceiver");
        factory = new GenericFactory(user3);

        evc = new EthereumVaultConnector();
        protocolConfig = new ProtocolConfig(admin, protocolFeeReceiver);
        balanceTracker = address(new MockBalanceTracker());
        oracle = new MockPriceOracle();
        unitOfAccount = address(1);
        permit2 = address(0);
        sequenceRegistry = address(new SequenceRegistry());
        integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, balanceTracker, permit2);

        initializeModule = address(new Initialize(integrations));
        tokenModule = address(new Token(integrations));
        vaultModule = address(new Vault(integrations));
        borrowingModule = address(new Borrowing(integrations));
        liquidationModule = address(new Liquidation(integrations));
        riskManagerModule = address(new RiskManager(integrations));
        balanceForwarderModule = address(new BalanceForwarder(integrations));
        governanceModule = address(new Governance(integrations));

        modules = Dispatch.DeployedModules({
            initialize: initializeModule,
            token: tokenModule,
            vault: vaultModule,
            borrowing: borrowingModule,
            liquidation: liquidationModule,
            riskManager: riskManagerModule,
            balanceForwarder: balanceForwarderModule,
            governance: governanceModule
        });

        address evaultImpl = address(new EVault(integrations, modules));

        factory.setImplementation(evaultImpl);

        string memory result = vm.serializeAddress("coreAddresses", "evc", address(evc));
        result = vm.serializeAddress("coreAddresses", "eVaultFactory", address(factory));
        vm.writeJson(result, "./script/dev-ctx/addresses/31337/CoreAddresses.json");
    }

    function genAsset(string memory symbol, uint8 decimals) internal returns (Asset memory a) {
        a.symbol = symbol;
        a.asset = address(new TestERC20(string(abi.encodePacked(symbol, " Token")), symbol, decimals, false));
        a.vault = factory.createProxy(address(0), true, abi.encodePacked(a.asset, address(oracle), unitOfAccount));
        IEVault(a.vault).setHookConfig(address(0), 0);
        IEVault(a.vault).setInterestRateModel(address(new IRMTestDefault()));
        IEVault(a.vault).setMaxLiquidationDiscount(0.2e4);
        IEVault(a.vault).setFeeReceiver(feeReceiver);
    }

    function deployAssets() internal {
        assets.push(genAsset("WETH", 18));
        assets.push(genAsset("wstETH", 18));
        assets.push(genAsset("USDC", 6));
        assets.push(genAsset("USDT", 6));

        for (uint256 i; i < assets.length; ++i) {
            oracle.setPrice(assets[i].vault, unitOfAccount, 1 ether); // FIXME

            for (uint256 j; j < assets.length; ++j) {
                if (i == j) continue;
                IEVault(assets[i].vault).setLTV(assets[j].vault, 0.88e4, 0.9e4, 0);
            }
        }

        address[] memory vaults = new address[](assets.length);
        for (uint256 i; i < assets.length; ++i) {
            vaults[i] = assets[i].vault;
        }

        string memory result = vm.serializeAddress("products", "vaults", vaults);
        string memory obj = vm.serializeString("products2", "testing-product", result);
        vm.writeJson(obj, "./script/dev-ctx/labels/31337/products.json");
    }

    function deployEulerSwap() internal {
        hub = new EulerSwapHub(address(evc), address(factory));
        periphery = new EulerSwapPeriphery();

        string memory result = vm.serializeAddress("eulerSwap", "eulerSwapHub", address(hub));
        result = vm.serializeAddress("eulerSwap", "eulerSwapPeriphery", address(periphery));
        vm.writeJson(result, "./script/dev-ctx/addresses/31337/EulerSwapAddresses.json");
    }

    function setupUsers() internal {
        IEVault eUSDC = IEVault(assets[2].vault);
        TestERC20 assetUSDC = TestERC20(eUSDC.asset());

        IEVault eUSDT = IEVault(assets[3].vault);
        TestERC20 assetUSDT = TestERC20(eUSDT.asset());

        // user2 is passive depositor
        vm.startBroadcast(user2PK);

        assetUSDC.mint(user2, 1000000e6);
        assetUSDT.mint(user2, 1000000e6);

        assetUSDC.approve(address(eUSDC), type(uint256).max);
        assetUSDT.approve(address(eUSDT), type(uint256).max);

        eUSDC.deposit(1000000e6, user2);
        eUSDT.deposit(1000000e6, user2);

        vm.stopBroadcast();

        // user0 is going to setup a position
        vm.startBroadcast(user0PK);

        assetUSDC.mint(user0, 100000e6);
        assetUSDC.approve(address(eUSDC), type(uint256).max);
        eUSDC.deposit(100000e6, user0);

        evc.enableCollateral(user0, address(eUSDC));
        evc.enableController(user0, address(eUSDT));
        eUSDT.borrow(80000e6, user0);

        vm.stopBroadcast();
    }
}
