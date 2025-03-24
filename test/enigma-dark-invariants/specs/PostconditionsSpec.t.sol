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

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         RESERVES                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant HSPOST_RESERVES_A = "HSPOST_RESERVES_A: If there is debt in tokenIn, the debt must be repaid";

    string constant HSPOST_RESERVES_B =
        "HSPOST_RESERVES_B: If amountOut does not exceed tokenOut collateral, tokenOut amount is withdrawn";

    string constant HSPOST_RESERVES_C =
        "HSPOST_RESERVES_C: If amountIn tokenOut collateral, a specific amountOut is borrowed";
}
