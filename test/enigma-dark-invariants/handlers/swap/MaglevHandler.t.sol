// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMaglevBase} from "src/interfaces/IMaglevBase.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title MaglevHandler
/// @notice Handler test contract for a set of actions
abstract contract MaglevHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    address roundtripSwapActor;
    address receiver;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function swap(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In, uint8 i) public setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        receiver = roundtripSwapActor == address(0) ? _getRandomActor(i) : roundtripSwapActor;

        address target = address(maglev);

        require(amount0Out > 1 || amount1Out > 1, "MaglevHandler: Invalid amount out");

        if (amount0In > 0) {
            _transferByActor(address(assetTST), address(maglev), amount0In);
        }

        if (amount1In > 0) {
            _transferByActor(address(assetTST2), address(maglev), amount1In);
        }

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IMaglevBase.swap.selector, amount0Out, amount1Out, receiver, ""));

        delete receiver;

        if (roundtripSwapActor != address(0)) require(success);

        if (success) {
            _after();

            _commonPostconditions(amount0Out, amount1Out, amount0In, amount1In);

            if (curve == Curve.EULER_SWAP) {
                _eulerSwapPostconditions();
            } else if (curve == Curve.PRODUCT) {
                _constantProductPostconditions();
            } else {
                _constantSumPostconditions();
            }

            assert(false);
        }
    }

    function roundtripSwap(uint256 amount, uint8 i) external setup {
        uint256 amount0Out;
        uint256 amount1Out;
        uint256 amount0In;
        uint256 amount1In;

        IERC20 assetTSTIn = IERC20(_getRandomBaseAsset(i));
        roundtripSwapActor = address(actor);

        // SWAP 1

        uint256 actorInBalanceBefore = assetTSTIn.balanceOf(roundtripSwapActor);

        if (i % 2 == 0) {
            // token0 -> token1 case
            amount0In = amount;
            amount1Out = maglev.quoteExactInput(address(assetTST), address(assetTST2), amount0In);
        } else {
            // token1 -> token0 case
            amount1In = amount;
            amount0Out = maglev.quoteExactInput(address(assetTST2), address(assetTST), amount1In);
        }

        swap(amount0Out, amount1Out, amount1In, amount0In, 0);

        // SWAP 2

        if (i % 2 == 0) {
            // token0 -> token1 case
            amount1In = amount1Out;
            amount0Out = maglev.quoteExactInput(address(assetTST2), address(assetTST), amount1In);
        } else {
            // token1 -> token0 case
            amount0In = amount0Out;
            amount1Out = maglev.quoteExactInput(address(assetTST), address(assetTST2), amount0In);
        }

        swap(amount0Out, amount1Out, amount1In, amount0In, 0);

        uint256 actorInBalanceAfter = assetTSTIn.balanceOf(roundtripSwapActor);

        // HSPOST
        assertLe(actorInBalanceAfter, actorInBalanceBefore, HSPOST_SWAP_B);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HSPOST: SWAP                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Postconditions common to all three curves
    function _commonPostconditions(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In)
        internal
    {
        if (amount0Out > 0) {
            assertEq(
                defaultVarsBefore.users[receiver].assetTSTBalance,
                defaultVarsBefore.users[receiver].assetTSTBalance + amount0Out - amount0In,
                HSPOST_SWAP_C
            );
        }

        if (amount1Out > 0) {
            assertEq(
                defaultVarsBefore.users[receiver].assetTST2Balance,
                defaultVarsBefore.users[receiver].assetTST2Balance + amount1Out - amount1In,
                HSPOST_SWAP_C
            );
        }
        assertGe(defaultVarsBefore.holderNAV, defaultVarsAfter.holderNAV, HSPOST_SWAP_A);
    }

    /// @notice Postconditions for EulerSwap curve
    function _eulerSwapPostconditions() internal {
        // TODO Implement postconditions
    }

    /// @notice Postconditions for ConstantProduct curve
    function _constantProductPostconditions() internal {
        // TODO Implement postconditions
    }

    /// @notice ºPostconditions for ConstantSum curve
    function _constantSumPostconditions() internal {
        // TODO Implement postconditions
    }
}
