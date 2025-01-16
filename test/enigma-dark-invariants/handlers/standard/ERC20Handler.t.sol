// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title ERC20Handler
/// @notice Handler test contract for a set of actions
abstract contract ERC20Handler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function approve(uint256 amount, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address spender = _getRandomActor(i);

        // Get one of the vaults randomly
        address target = _getRandomVault(j);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));

        if (success) {
            _after();
        } else {
            revert("ERC20Handler: approve failed");
        }
    }

    function transfer(uint256 amount, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address to = _getRandomActor(i);

        // Get one of the vaults randomly
        address target = _getRandomVault(j);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));

        if (success) {
            _after();
        } else {
            revert("ERC20Handler: transfer failed");
        }
    }

    function transferFrom(uint256 amount, uint8 i, uint8 j, uint8 k) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address from = _getRandomActor(i);
        // Get one of the three actors randomly
        address to = _getRandomActor(j);

        // Get one of the vaults randomly
        address target = _getRandomVault(k);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));

        if (success) {
            _after();
        } else {
            revert("ERC20Handler: transferFrom failed");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
