// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMaglevBase} from "src/interfaces/IMaglevBase.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title MaglevHandler
/// @notice Handler test contract for a set of actions
abstract contract MaglevHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function swap(uint256 amount0Out, uint256 amount1Out, uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address to = _getRandomActor(i);

        address target = address(maglev);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IMaglevBase.swap.selector, amount0Out, amount1Out, to, ""));

        if (success) {
            _after();
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
