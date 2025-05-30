// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries

// Contracts
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {ProtocolConfig} from "evk/ProtocolConfig/ProtocolConfig.sol";
import {EulerSwap} from "src/EulerSwap.sol";
import {EulerSwapPeriphery} from "src/EulerSwapPeriphery.sol";
import {EulerSwapFactory} from "src/EulerSwapFactory.sol";

// Interfaces
import {IEVault} from "evk/EVault/IEVault.sol";

// Mock Contracts
import {TestERC20} from "test/enigma-dark-invariants/utils/mocks/TestERC20.sol";
import {MockPriceOracle} from "../utils/mocks/MockPriceOracle.sol";

// Utils
import {Actor} from "../utils/Actor.sol";

/// @notice BaseStorage contract for all test contracts, works in tandem with BaseTest
abstract contract BaseStorage {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONSTANTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    uint256 constant MAX_TOKEN_AMOUNT = 1e29;

    uint256 constant ONE_DAY = 1 days;
    uint256 constant ONE_MONTH = ONE_YEAR / 12;
    uint256 constant ONE_YEAR = 365 days;

    uint256 internal constant NUMBER_OF_ACTORS = 3;
    uint256 internal constant INITIAL_ETH_BALANCE = 1e26;
    uint256 internal constant INITIAL_COLL_BALANCE = 1e21;

    address internal constant unitOfAccount = address(1);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTORS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Stores the actor during a handler call
    Actor internal actor;

    /// @notice Mapping of fuzzer user addresses to actors
    mapping(address => Actor) internal actors;

    /// @notice Array of all actor addresses
    address[] internal actorAddresses;

    /// @notice The address that is targeted when executing an action
    address internal targetActor;

    /// @notice The account that owns the euler-swap liqudity
    address internal holder;

    address internal feeRecipient;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       SUITE STORAGE                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Generic factory
    GenericFactory factory;

    /// @notice System vaults
    IEVault eTST;
    IEVault eTST2;

    /// @notice Mock assets
    TestERC20 assetTST;
    TestERC20 assetTST2;

    /// @notice EulerSwap contracts
    EulerSwap eulerSwap;
    EulerSwapPeriphery periphery;
    EulerSwapFactory eulerSwapfactory;

    /// @notice Extra contracts
    MockPriceOracle oracle;
    ProtocolConfig protocolConfig;
    address balanceTracker;
    address sequenceRegistry;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       EXTRA VARIABLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Array of base assets for the suite
    address[] internal baseAssets;

    /// @notice Array of vaults for the suite
    address[] internal vaults;

    /// @notice Evc contract
    EthereumVaultConnector evc;

    /// @notice Permit2 contract
    address permit2;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          STRUCTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
