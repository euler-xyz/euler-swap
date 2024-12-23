// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// modules Actions Handler contracts,
import {EVCHandler} from "./handlers/euler/EVCHandler.t.sol";
import {ERC20Handler} from "./handlers/standard/ERC20Handler.t.sol";
import {ERC4626Handler} from "./handlers/standard/ERC4626Handler.t.sol";
import {MaglevHandler} from "./handlers/swap/MaglevHandler.t.sol";

// Simulator Handler contracts,
import {DonationAttackHandler} from "./handlers/simulators/DonationAttackHandler.t.sol";
import {PriceOracleHandler} from "./handlers/simulators/PriceOracleHandler.t.sol";

/// @notice Helper contract to aggregate all handler contracts, inherited in BaseInvariants
abstract contract HandlerAggregator is
    EVCHandler, // Euler handlers
    ERC20Handler, // Module handlers
    ERC4626Handler,
    MaglevHandler,
    DonationAttackHandler, // Simulator handlers
    PriceOracleHandler
{
    /// @notice Helper function in case any handler requires additional setup
    function _setUpHandlers() internal {}
}
