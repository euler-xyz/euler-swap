// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IEulerSwap} from "src/interfaces/IEulerSwap.sol";

// Contracts
import {EulerSwap} from "src/EulerSwap.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title EulerSwapSetupHandler
/// @notice Handler test contract for a set of actions
abstract contract EulerSwapSetupHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setupEulerSwap(
        uint8 leverage,
        uint112 initialAmount0,
        uint112 initialAmount1,
        uint256 fee,
        IEulerSwap.CurveParams memory curveParams
    ) public eulerSwapNotDeployed {
        /// --- CLAMPING PARAMETERS ---

        // Restrict leverage to a maximum of x10
        leverage = uint8(clampBetween(leverage, MIN_LEVERAGE, MAX_LEVERAGE));

        (initialAmount0, initialAmount1) = _generateBalancedReserves(initialAmount0, initialAmount1, curveParams);

        // Ensure initial deposit amounts are at least 1000 tokens and within leverage limits
        initialAmount0 = uint112(clampBetween(initialAmount0, 1000e18, type(uint112).max / leverage));
        initialAmount1 = uint112(clampBetween(initialAmount1, 1000e18, type(uint112).max / leverage));

        // Calculate maximum debt limits based on leverage
        uint112 debtLimit0 = initialAmount0 * leverage;
        uint112 debtLimit1 = initialAmount1 * leverage;

        // Clamp price values within a reasonable range (0.1 to 10)
        curveParams.priceX = clampBetween(curveParams.priceX, 0.1e16, 1e36); // TODO Integrate oracle price
        curveParams.priceY = clampBetween(curveParams.priceY, 0.1e16, 1e36);

        // Clamp concentration between 0.1e18 and 1e18
        curveParams.concentrationX = clampBetween(curveParams.concentrationX, 0.1e18, 1e18); // TODO Implement test variants with imbalanced initial pools where concentrationX != concentrationY and reserves don't match equilibrium values - this should verify curve behavior under asymmetric conditions
        curveParams.concentrationY = clampBetween(curveParams.concentrationY, 0.1e18, 1e18);

        // Check equilibriumReserves are on the curve

        /// --- INITIAL DEPOSITS ---

        // Deposit initial funds into vaults on behalf of the holder
        vm.prank(holder);
        eTST.deposit(initialAmount0, holder);

        vm.prank(holder);
        eTST2.deposit(initialAmount1, holder);

        /// --- DEPLOY EULER SWAP CONTRACT ---

        assertTrue(
            _createEulerSwap(
                debtLimit0,
                debtLimit1,
                fee,
                curveParams.priceX,
                curveParams.priceY,
                curveParams.concentrationX,
                curveParams.concentrationY
            ),
            "EulerSwapSetupHandler: failed to create EulerSwap"
        );

        /// --- SETUP ACTORS' TOKEN APPROVALS ---

        // Configure actors' token approvals for the eulerSwap contract
        address[] memory contracts = new address[](1);
        contracts[0] = address(eulerSwap);

        _setupActorApprovals(baseAssets, contracts);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                EULER-SWAP SPECIFIC HELPERS                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
