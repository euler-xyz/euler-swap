// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title PostconditionsSpec
/// @notice Postcoditions specification for the protocol
/// @dev Contains pseudo code and description for the postcondition properties in the protocol
abstract contract PostconditionsSpec {
    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                      PROPERTY TYPES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    
    /// - POSTCONDITIONS:
    ///   - Properties that should hold true after an action is executed.
    ///   - Implemented in the /hooks and /handlers folders.
    ///   - There are two types of POSTCONDITIONS:
    ///     - GLOBAL POSTCONDITIONS (GPOST): 
    ///       - Properties that should always hold true after any action is executed.
    ///       - Checked in the `_checkPostConditions` function within the HookAggregator contract.
    ///     - HANDLER-SPECIFIC POSTCONDITIONS (HSPOST): 
    ///       - Properties that should hold true after a specific action is executed in a specific context.
    ///       - Implemented within each handler function, under the HANDLER-SPECIFIC POSTCONDITIONS section.
    
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          SWAP                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant HSPOST_SWAP_A = "HSPOST_SWAP_A: Holder's NAV should increase monotonically";

    string constant HSPOST_SWAP_B = "HSPOST_SWAP_B: Swapping back and forth does not lead to a profit";

    string constant HSPOST_SWAP_C = "HSPOST_SWAP_C: User should receive the amount out specified after a swap";

    string constant HSPOST_SWAP_D = "HSPOST_SWAP_D: Successful swaps are always inside the swap limits";

    string constant HSPOST_SWAP_E = "HSPOST_SWAP_E: Swaps with quoted amounts should always be successful";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         RESERVES                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant HSPOST_RESERVES_A =
        "HSPOST_RESERVES_A: When positive delta exists, debt must decrease by min(delta, previous_debt)";

    string constant HSPOST_RESERVES_B =
        "HSPOST_RESERVES_B: When positive delta is greater than previous debt, debt is fully repaid";

    string constant HSPOST_RESERVES_C =
        "HSPOST_RESERVES_C: When positive delta is greater than previous debt, the excess delta is added to assets";

    string constant HSPOST_RESERVES_D =
        "HSPOST_RESERVES_D: When negative delta exists, assets must decrease by min(delta, previous_assets)";

    string constant HSPOST_RESERVES_E =
        "HSPOST_RESERVES_E: When negative delta is greater than previous assets, assets are fully depleted";

    string constant HSPOST_RESERVES_F =
        "HSPOST_RESERVES_F: When negative delta is greater than previous assets, the deficit is added to debt";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          DEBT                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant HSPOST_DEBT_A = "HSPOST_DEBT_A: Debt on an asset after a swap should never exceed the debt limit";
}
