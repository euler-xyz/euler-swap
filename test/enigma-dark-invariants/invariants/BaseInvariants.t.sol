// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import "forge-std/console.sol";

/// @title BaseInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract BaseInvariants is HandlerAggregator {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BASE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_BASE_A() internal {}
}
