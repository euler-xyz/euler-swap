// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title NonRevertPropertiesSpec
/// @notice Properties specification for the protocol
/// @dev Contains pseudo code and description for the invariant properties in the protocol
abstract contract NonRevertPropertiesSpec {
    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                      PROPERTY TYPES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// - NON REVERT (NR): 
    ///   - Properties that assert a specific function should never revert, or only revert under 
    ///   certain defined conditions.

    /////////////////////////////////////////////////////////////////////////////////////////////*/

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BASE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant NR_BASE_A = "NR_BASE_A: updateInterestAccrued should not revert";
}
