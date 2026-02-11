// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Hook Contracts
import {DefaultBeforeAfterHooks} from "./DefaultBeforeAfterHooks.t.sol";

/// @title HookAggregator
/// @notice Helper contract to aggregate all before / after hook contracts, inherited on each handler
abstract contract HookAggregator is DefaultBeforeAfterHooks {
    /// @notice Initializer for the hooks
    function _setUpHooks() internal {
        _setUpDefaultHooks();
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                         HOOKS                                             //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Modular hook selector, per module
    function _before() internal {
        _defaultHooksBefore();
    }

    /// @notice Modular hook selector, per module
    function _after() internal {
        _defaultHooksAfter();

        // POST-CONDITIONS
        _checkPostConditions();
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                   POSTCONDITION CHECKS                                    //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Postconditions for the handlers
    function _checkPostConditions() internal {
        // Check general postconditions
        _checkGeneralPostConditions();

        // Check user postconditions
        for (uint256 i; i < actorAddresses.length; i++) {
            _checkUserPostConditions(actorAddresses[i]);
        }
    }

    function _checkGeneralPostConditions() internal {
        // Check general postconditions
    }

    /// @notice Postconditions for each user
    function _checkUserPostConditions(address user) internal {
        // Check user postconditions
    }
}
