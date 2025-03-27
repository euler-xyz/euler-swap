// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title InvariantsSpec
/// @notice Invariants specification for the protocol
/// @dev Contains pseudo code and description for the invariant properties in the protocol
abstract contract InvariantsSpec {
    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                      PROPERTY TYPES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// - INVARIANTS (INV): 
    ///   - Properties that should always hold true in the system. 
    ///   - Implemented in the /invariants folder.

    /////////////////////////////////////////////////////////////////////////////////////////////*/

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         CORE                                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant INV_CORE_A = "INV_CORE_A: At most one of vault0 or vault1 has debt (unless the CDP is under water)";

    string constant INV_CORE_B = "INV_CORE_B: Account should never be liquidatable";

    string constant INV_CORE_C = "INV_CORE_C: The curve invariant must always hold";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    STATE MANAGEMENT                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant INV_STATE_A = "INV_STATE_A: Status should only transition in valid ways";

    string constant INV_STATE_B = "INV_STATE_B: Asset addresses should maintain correct ordering";

    string constant INV_STATE_C = "INV_STATE_C: If there's debt, controller should be enabled";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       DEBT LIMIT                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant INV_DL_A = "INV_DL_A: Leverage should not exceed debt limits";

    string constant INV_DL_B = "INV_DL_B: Total borrowed amount should never exceed leverage * initial reserves"; // TODO

    // TODO: Implement invariants based on ChainSecurity report formulas
    // TODO: Implement invariants for LTV checks from ChainSecurity report -> no implemented, checked with liquidation invariant
    // TODO: Implement invariants for liquidation checks from ChainSecurity report -> X
    // TODO: Implement invariants for reserve desynchronization from ChainSecurity report -> NO
    // TODO: Implement invariant to ensure debt never exceeds the debt limit -> X 
    // TODO: Implement invariants from the team call notes -> TODO
    // TODO: Review the trust model of the protocol as outlined in the ChainSecurity report -> TODO
    // TODO: Review the binary search implementation -> TODO
    // TODO: Implement check for rounding error amplification (5.5) -> TODO
    // TODO: Implement check to prevent Donation Attack resulting in DoS (5.1), ensuring the "quote" rule makes swap always succeed -> TODO
    // TODO: Implement invariant for relation between f and f inverse -> TODO
}
