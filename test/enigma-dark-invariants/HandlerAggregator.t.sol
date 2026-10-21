// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// modules Actions Handler contracts,
import {EVCHandler} from "./handlers/euler/EVCHandler.t.sol";
import {ERC20Handler} from "./handlers/standard/ERC20Handler.t.sol";
import {ERC4626Handler} from "./handlers/standard/ERC4626Handler.t.sol";
import {EulerSwapHandler} from "./handlers/swap/EulerSwapHandler.t.sol";
import {EulerSwapPeripheryHandler} from "./handlers/swap/EulerSwapPeripheryHandler.t.sol";
import {EulerSwapSetupHandler} from "./handlers/setup/EulerSwapSetupHandler.t.sol";

// Simulator Handler contracts,
import {DonationAttackHandler} from "./handlers/simulators/DonationAttackHandler.t.sol";
import {PriceOracleHandler} from "./handlers/simulators/PriceOracleHandler.t.sol";

/// @notice Helper contract to aggregate all handler contracts, inherited in BaseInvariants
abstract contract HandlerAggregator is
    EVCHandler, // Euler handlers
    ERC20Handler, // Standard Handlers
    ERC4626Handler,
    EulerSwapHandler, // Swap Handlers
    EulerSwapPeripheryHandler,
    EulerSwapSetupHandler, // Setup Handlers
    DonationAttackHandler, // Simulator handlers
    PriceOracleHandler
{
    /// @notice Helper function in case any handler requires additional setup
    function _setUpHandlers() internal {}
}
