// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {BaseHooks} from "../base/BaseHooks.t.sol";

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626Handler} from "../handlers/interfaces/IERC4626Handler.sol";

/// @title Default Before After Hooks
/// @notice Helper contract for before and after hooks
/// @dev This contract is inherited by handlers
abstract contract DefaultBeforeAfterHooks is BaseHooks {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         STRUCTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    struct User {
        uint256 assetTSTBalance;
        uint256 assetTST2Balance;
    }

    struct DefaultVars {
        mapping(address => User) users;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       HOOKS STORAGE                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    DefaultVars defaultVarsBefore;
    DefaultVars defaultVarsAfter;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           SETUP                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Default hooks setup
    function _setUpDefaultHooks() internal {}

    /// @notice Helper to initialize storage arrays of default vars
    function _setUpDefaultVars(DefaultVars storage _dafaultVars) internal {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HOOKS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _defaultHooksBefore() internal {
        // Default values
        _setVaultValues(defaultVarsBefore);
        // Health & user account data
        _setUserValues(defaultVarsBefore);
    }

    function _defaultHooksAfter() internal {
        // Default values
        _setVaultValues(defaultVarsAfter);
        // Health & user account data
        _setUserValues(defaultVarsAfter);
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                       HELPERS                                             //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    function _setVaultValues(DefaultVars storage _defaultVars) internal {}

    function _setUserValues(DefaultVars storage _defaultVars) internal {
        for (uint256 i; i < actorAddresses.length; i++) {
            _setUserValuesPerActor(_defaultVars.users[actorAddresses[i]]);
        }
    }

    function _setUserValuesPerActor(User storage _user) internal {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   POST CONDITIONS: BASE                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_GPOST_BASE_A() internal {}
}
