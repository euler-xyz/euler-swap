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
        // Holder
        int256 holderNAV;
        uint256 holderETSTAssets;
        uint256 holderETST2Assets;
        uint256 holderETSTDebt;
        uint256 holderETST2Debt;
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
        _setDefaultValues(defaultVarsBefore);
        // Health & user account data
        _setUserValues(defaultVarsBefore);
    }

    function _defaultHooksAfter() internal {
        // Default values
        _setDefaultValues(defaultVarsAfter);
        // Health & user account data
        _setUserValues(defaultVarsAfter);
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                       HELPERS                                             //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    function _setDefaultValues(DefaultVars storage _defaultVars) internal {
        // Holder
        _defaultVars.holderNAV = _getHolderNAV();
        _defaultVars.holderETSTAssets = eTST.convertToAssets(eTST.balanceOf(holder));
        /// @dev adding eulerSwap balance to take donations into account
        _defaultVars.holderETST2Assets = eTST2.convertToAssets(eTST2.balanceOf(holder));
        _defaultVars.holderETSTDebt = eTST.debtOf(holder);
        _defaultVars.holderETST2Debt = eTST2.debtOf(holder);
    }

    function _setUserValues(DefaultVars storage _defaultVars) internal {
        for (uint256 i; i < actorAddresses.length; i++) {
            address actorAddress_ = actorAddresses[i];
            _setUserValuesPerActor(_defaultVars.users[actorAddress_], actorAddress_);
        }
    }

    function _setUserValuesPerActor(User storage _user, address _actorAddress) internal {
        _user.assetTSTBalance = assetTST.balanceOf(_actorAddress);
        _user.assetTST2Balance = assetTST2.balanceOf(_actorAddress);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   POST CONDITIONS: BASE                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_GPOST_BASE_A() internal {}
}
