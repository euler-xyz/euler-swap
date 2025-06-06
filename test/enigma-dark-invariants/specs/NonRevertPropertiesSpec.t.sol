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

    string constant NR_QUOTE_A = "NR_QUOTE_A: quoteExactInput should not revert";

    string constant NR_QUOTE_B = "NR_QUOTE_B: quoteExactOutput should not revert";
}
