// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEVault} from "evk/EVault/IEVault.sol";

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import "forge-std/console.sol";

/// @title BaseInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract BaseInvariants is HandlerAggregator {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          CORE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_CORE_A() internal {
        assertFalse(eTST.debtOf(holder) != 0 && eTST2.debtOf(holder) != 0, INV_CORE_A);
    }

    function assert_INV_CORE_B() internal {
        address[] memory controllers = evc.getControllers(holder);

        address controller = controllers[0];

        (uint256 collateralValue, uint256 liabilityValue) =
            IEVault(controller).accountLiquidity(eulerSwap.eulerAccount(), false);

        assertTrue(collateralValue > liabilityValue, INV_CORE_B);
    }

    function assert_INV_CORE_C() internal {
        // The curve invariant must always hold
        (uint112 reserve0, uint112 reserve1,) = eulerSwap.getReserves();
        assertTrue(eulerSwap.verify(reserve0, reserve1), INV_CORE_C);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     STATE MANAGEMENT                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_INV_STATE_A() internal {
        (,, uint32 status) = eulerSwap.getReserves();

        assertTrue(status == 0 || status == 1 || status == 2, INV_STATE_A);
    }

    function assert_INV_STATE_B() internal {
        assertTrue(eulerSwap.asset0() < eulerSwap.asset1(), INV_STATE_B);
    }

    function assert_INV_STATE_C() internal {
        // Controller should be properly enabled/disabled
        bool controller0 = evc.isControllerEnabled(eulerSwap.eulerAccount(), address(eTST));
        bool controller1 = evc.isControllerEnabled(eulerSwap.eulerAccount(), address(eTST2));

        // If there's debt, controller should be enabled
        assertTrue(
            (eTST.debtOf(eulerSwap.eulerAccount()) == 0 || controller0)
                && (eTST2.debtOf(eulerSwap.eulerAccount()) == 0 || controller1),
            INV_STATE_C
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         DEBT LIMIT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    function assert_INV_DL_A() internal {
        // Total borrowed amount should never exceed leverage * initial reserves
        uint256 totalDebt0 = eTST.debtOf(eulerSwap.eulerAccount());
        uint256 totalDebt1 = eTST2.debtOf(eulerSwap.eulerAccount());

        assertLe(totalDebt0, uint256(eulerSwap.equilibriumReserve0()) * MAX_LEVERAGE, INV_DL_A);
        assertLe(totalDebt1, uint256(eulerSwap.equilibriumReserve1()) * MAX_LEVERAGE, INV_DL_A);
    }
}
