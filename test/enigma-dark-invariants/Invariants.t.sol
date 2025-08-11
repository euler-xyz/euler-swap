// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Invariant Contracts
import {BaseInvariants} from "./invariants/BaseInvariants.t.sol";

/// @title Invariants
/// @notice Wrappers for the protocol invariants implemented in each invariants contract
/// @dev recognised by Echidna when property mode is activated
/// @dev Inherits BaseInvariants
abstract contract Invariants is BaseInvariants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     BASE INVARIANTS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_CORE_INVARIANTS() public returns (bool) {
        if (address(eulerSwap) != address(0)) {
            assert_INV_CORE_A();
            assert_INV_CORE_C();
        }

        return true;
    }

    function echidna_STATE_INVARIANTS() public returns (bool) {
        if (address(eulerSwap) != address(0)) {
            assert_INV_STATE_A();
            assert_INV_STATE_B();
            assert_INV_STATE_C();
        }

        return true;
    }

    function echidna_DEBT_LIMIT_INVARIANTS() public returns (bool) {
        if (address(eulerSwap) != address(0)) {
            assert_INV_DL_A();
        }

        return true;
    }
}
