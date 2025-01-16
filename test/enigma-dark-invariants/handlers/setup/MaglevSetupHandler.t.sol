// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {MaglevBase} from "src/MaglevBase.sol";
import {MaglevEulerSwap} from "src/MaglevEulerSwap.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title MaglevSetupHandler
/// @notice Handler test contract for a set of actions
abstract contract MaglevSetupHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setupMaglev(
        uint8 leverage,
        uint112 initialAmount0,
        uint112 initialAmount1,
        uint256 fee,
        Curve, /*_curveType*/
        MaglevEulerSwap.EulerSwapParams memory eulerSwapParams
    ) public maglevNotDeployed {
        // Clamp leverage at x10
        leverage = uint8(clampBetween(leverage, 1, 10));

        // Clamp minimum amount at 1000 tokens
        initialAmount0 = uint112(clampBetween(initialAmount0, 1000e18, type(uint112).max));
        initialAmount1 = uint112(clampBetween(initialAmount1, 1000e18, type(uint112).max));

        uint112 debtLimit0 = initialAmount0 * leverage;
        uint112 debtLimit1 = initialAmount1 * leverage;

        // Clamp concentration between 0.1e18 and 1e18
        eulerSwapParams.priceX = clampBetween(eulerSwapParams.priceX, 0.1e18, 1e18);
        eulerSwapParams.priceY = clampBetween(eulerSwapParams.priceY, 0.1e18, 1e18);

        // Deposit initial funds on the vaults as the holder
        vm.prank(holder);
        eTST.deposit(initialAmount0, holder);
        vm.prank(holder);
        eTST2.deposit(initialAmount1, holder);

        // Setup the maglev params
        MaglevBase.BaseParams memory baseParams = MaglevBase.BaseParams({
            evc: address(evc),
            vault0: address(eTST),
            vault1: address(eTST2),
            myAccount: holder,
            debtLimit0: debtLimit0,
            debtLimit1: debtLimit1,
            fee: fee
        });

        Curve _curveType = Curve.EULER_SWAP; // TODO remove hardcoded curve type -> try other curves on different instances

        /// Deploy the specific curve type maglev contract
        if (_curveType == Curve.EULER_SWAP) {
            _deployMaglevEulerSwap(baseParams, eulerSwapParams);
        } else if (_curveType == Curve.PRODUCT) {
            _deployMaglevConstantProduct(baseParams);
        } else {
            _deployMaglevConstantSum(baseParams);
        }

        // Set maglev as operator for the lp and call configure
        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);
        maglev.configure();

        // Setup actors token approvals to maglev
        address[] memory contracts = new address[](1);
        contracts[0] = address(maglev);

        _setupActorApprovals(baseAssets, contracts);
    }
}
