// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title ERC4626Handler
/// @notice Handler test contract for a set of actions
abstract contract ERC4626Handler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function deposit(uint256 assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        address target = _getRandomVault(j);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC4626.deposit.selector, assets, receiver));

        if (success) {
            _after();
        } else {
            revert("ERC4626Handler: deposit failed");
        }
    }

    function mint(uint256 shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        address target = _getRandomVault(j);

        _before();
        (success, returnData) = actor.proxy(target, abi.encodeWithSelector(IERC4626.mint.selector, shares, receiver));

        if (success) {
            _after();
        } else {
            revert("ERC4626Handler: mint failed");
        }
    }

    function withdraw(uint256 assets, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        address target = _getRandomVault(j);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IERC4626.withdraw.selector, assets, receiver, address(actor)));

        if (success) {
            _after();
        } else {
            revert("ERC4626Handler: withdraw failed");
        }
    }

    function redeem(uint256 shares, uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address receiver = _getRandomActor(i);

        // Get one of the vaults randomly
        address target = _getRandomVault(j);

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IERC4626.redeem.selector, shares, receiver, address(actor)));

        if (success) {
            _after();
        } else {
            revert("ERC4626Handler: redeem failed");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
