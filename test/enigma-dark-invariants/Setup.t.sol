// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Utils
import "forge-std/console.sol";

// Libraries
import {DeployPermit2} from "./utils/DeployPermit2.sol";

// Contracts
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {ProtocolConfig} from "evk/ProtocolConfig/ProtocolConfig.sol";
import {SequenceRegistry} from "evk/SequenceRegistry/SequenceRegistry.sol";
import {Base} from "evk/EVault/shared/Base.sol";
import {Dispatch} from "evk/EVault/Dispatch.sol";
import {EVault} from "evk/EVault/EVault.sol";
import {MaglevBase} from "src/MaglevBase.sol";
import {MaglevConstantSum} from "src/MaglevConstantSum.sol";
import {MaglevConstantProduct} from "src/MaglevConstantProduct.sol";
import {MaglevEulerSwap} from "src/MaglevEulerSwap.sol";

// Modules
import {Initialize} from "evk/EVault/modules/Initialize.sol";
import {Token} from "evk/EVault/modules/Token.sol";
import {Vault} from "evk/EVault/modules/Vault.sol";
import {Borrowing} from "evk/EVault/modules/Borrowing.sol";
import {Liquidation} from "evk/EVault/modules/Liquidation.sol";
import {BalanceForwarder} from "evk/EVault/modules/BalanceForwarder.sol";
import {Governance} from "evk/EVault/modules/Governance.sol";
import {RiskManager} from "evk/EVault/modules/RiskManager.sol";
import {MockBalanceTracker} from "evk/../test/mocks/MockBalanceTracker.sol";

// Interfaces
import {IEVault} from "evk/EVault/IEVault.sol";
import {IRMTestDefault} from "evk-test/mocks/IRMTestDefault.sol";
import {IMaglevBase} from "src/interfaces/IMaglevBase.sol";

// Test Contracts
import {TestERC20} from "test/enigma-dark-invariants/utils/mocks/TestERC20.sol";
import {BaseTest} from "test/enigma-dark-invariants/base/BaseTest.t.sol";
import {MockPriceOracle} from "./utils/mocks/MockPriceOracle.sol";
import {Actor} from "./utils/Actor.sol";

/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract Setup is BaseTest {
    function _setUp(Curve _curveType) internal {
        // Deploy protocol contracts and protocol actors
        _deployEulerEnvContracts();

        // Deploy vaults
        _deployVaults();

        // Deploy actors
        _setUpActors();

        // Deploy and setup maglev
        _deployMaglev(_curveType);
    }

    /// @notice Deploy euler env contracts
    function _deployEulerEnvContracts() internal {
        // Deploy the EVC
        evc = new EthereumVaultConnector();

        // Deploy permit2 contract
        permit2 = DeployPermit2.deployPermit2();

        // Setup fee recipient
        feeRecipient = _makeAddr("feeRecipient");
        protocolConfig = new ProtocolConfig(address(this), feeRecipient);

        // Deploy the oracle and integrations
        balanceTracker = address(new MockBalanceTracker());
        oracle = new MockPriceOracle();
        sequenceRegistry = address(new SequenceRegistry());
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           VAULTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deployVaults() internal {
        // Deploy the modules
        Base.Integrations memory integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, balanceTracker, permit2);

        Dispatch.DeployedModules memory modules = Dispatch.DeployedModules({
            initialize: address(new Initialize(integrations)),
            token: address(new Token(integrations)),
            vault: address(new Vault(integrations)),
            borrowing: address(new Borrowing(integrations)),
            liquidation: address(new Liquidation(integrations)),
            riskManager: address(new RiskManager(integrations)),
            balanceForwarder: address(new BalanceForwarder(integrations)),
            governance: address(new Governance(integrations))
        });

        // Deploy the vault implementation
        address evaultImpl = address(new EVault(integrations, modules));

        // Deploy the vault factory and set the implementation
        factory = new GenericFactory(address(this));
        factory.setImplementation(evaultImpl);

        // Deploy base assets
        assetTST = new TestERC20("Test Token", "TST", 18);
        baseAssets.push(address(assetTST));

        assetTST2 = new TestERC20("Test Token 2", "TST2", 18);
        baseAssets.push(address(assetTST2));

        // Deploy the vaults
        eTST = _deployEVault(address(assetTST));
        vaults.push(address(eTST));

        eTST2 = _deployEVault(address(assetTST2));
        vaults.push(address(eTST2));
    }

    function _deployEVault(address asset) internal returns (IEVault eVault) {
        // Deploy the eTST
        eVault = IEVault(factory.createProxy(address(0), true, abi.encodePacked(asset, address(oracle), address(1))));

        // Configure the vault
        eVault.setHookConfig(address(0), 0);
        eVault.setInterestRateModel(address(new IRMTestDefault()));
        eVault.setMaxLiquidationDiscount(0.2e4);
        eVault.setFeeReceiver(feeRecipient);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           MAGLEV                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deployMaglev(Curve _curveType) internal {
        // Setup maglev lp as the first actor
        holder = address(actors[USER1]);

        /// @dev store the curve selected
        curve = _curveType;

        // Setup the maglev params
        MaglevBase.BaseParams memory baseParams = MaglevBase.BaseParams({
            evc: address(evc),
            vault0: address(eTST),
            vault1: address(eTST2),
            myAccount: holder,
            debtLimit0: 50e18, // TODO tweak these numbers
            debtLimit1: 50e18,
            fee: 0
        });

        /// @dev Switch between the different curves
        if (curve == Curve.EULER_SWAP) {
            _deployMaglevEulerSwap(baseParams);
        } else if (curve == Curve.PRODUCT) {
            _deployMaglevConstantProduct(baseParams);
        } else {
            _deployMaglevConstantSum(baseParams);
        }

        // Set maglev as operator for the lp and call configure
        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);
        maglev.configure();

        // Setup actors token approvals to maglev
        address[] memory contracts = new address[](1);
        contracts[0] = address(maglev);

        _setupActorApprovals(baseAssets, contracts);
    }

    function _deployMaglevEulerSwap(MaglevBase.BaseParams memory _baseParams) internal {
        maglev = IMaglevBase(
            address(
                new MaglevEulerSwap(
                    _baseParams,
                    MaglevEulerSwap.EulerSwapParams({
                        priceX: 1e18,
                        priceY: 1e18,
                        concentrationX: 0.4e18,
                        concentrationY: 0.85e18
                    })
                )
            )
        );
    }

    function _deployMaglevConstantProduct(MaglevBase.BaseParams memory _baseParams) internal {
        maglev = IMaglevBase(address(new MaglevConstantProduct(_baseParams)));
    }

    function _deployMaglevConstantSum(MaglevBase.BaseParams memory _baseParams) internal {
        maglev = IMaglevBase(
            address(
                new MaglevConstantSum(_baseParams, MaglevConstantSum.ConstantSumParams({priceX: 1e18, priceY: 1e18}))
            )
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTORS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy protocol actors and initialize their balances
    function _setUpActors() internal {
        // Initialize the three actors of the fuzzers
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        // Initialize the tokens array
        address[] memory tokens = new address[](2);
        tokens[0] = address(assetTST);
        tokens[1] = address(assetTST2);

        address[] memory contracts_ = new address[](2);
        contracts_[0] = address(eTST);
        contracts_[1] = address(eTST2);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deploy actor proxies and approve system contracts_
            address _actor = _setUpActor(addresses[i], tokens, contracts_);

            // Mint initial balances to actors
            for (uint256 j = 0; j < tokens.length; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }
            actorAddresses.push(_actor);
        }
    }

    /// @notice Deploy an actor proxy contract for a user address
    /// @param userAddress Address of the user
    /// @param tokens Array of token addresses
    /// @param contracts_ Array of contract addresses to aprove tokens to
    /// @return actorAddress Address of the deployed actor
    function _setUpActor(address userAddress, address[] memory tokens, address[] memory contracts_)
        internal
        returns (address actorAddress)
    {
        bool success;
        Actor _actor = new Actor(tokens, contracts_);
        actors[userAddress] = _actor;
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }

    function _setupActorApprovals(address[] memory tokens, address[] memory contracts_) internal {
        for (uint256 i; i < actorAddresses.length; i++) {
            for (uint256 j; j < tokens.length; j++) {
                for (uint256 k; k < contracts_.length; k++) {
                    _approve(tokens[j], actorAddresses[i], contracts_[k], type(uint256).max);
                }
            }
        }
    }
}
