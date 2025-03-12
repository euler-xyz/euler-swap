// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEulerSwapPeriphery} from "src/interfaces/IEulerSwapPeriphery.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title EulerSwapPeripheryHandler
/// @notice Handler test contract for a set of actions
abstract contract EulerSwapPeripheryHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function swapExactIn(uint256 amountIn, uint256 amountOutMin, bool dir) public setup eulerSwapDeployed {
        bool success;
        bytes memory returnData;

        address target = address(periphery);

        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);

        _before();
        (success, returnData) = actor.proxy(
            target,
            abi.encodeWithSelector(
                IEulerSwapPeriphery.swapExactIn.selector, address(eulerSwap), tokenIn, tokenOut, amountIn, amountOutMin
            )
        );

        if (success) {
            _after();

            // _eulerSwapPostconditions(amount0Out, amount1Out, amount0In, amount1In); // TODO check postconditions
        } else {
            revert("EulerSwapPeripheryHandler: swapExactIn failed");
        }
    }

    function swapExactOut(uint256 amountOut, uint256 amountInMax, bool dir) public setup eulerSwapDeployed {
        bool success;
        bytes memory returnData;

        address target = address(periphery);

        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);

        _before();
        (success, returnData) = actor.proxy(
            target,
            abi.encodeWithSelector(
                IEulerSwapPeriphery.swapExactOut.selector, address(eulerSwap), tokenIn, tokenOut, amountOut, amountInMax
            )
        );

        if (success) {
            _after();

            // _eulerSwapPostconditions(amount0Out, amount1Out, amount0In, amount1In); // TODO check postconditions
        } else {
            revert("EulerSwapPeripheryHandler: swapExactOut failed");
        }
    }

    function quoteExactInput(uint256 amountIn, bool dir) external eulerSwapDeployed {
        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);

        try periphery.quoteExactInput(address(eulerSwap), tokenIn, tokenOut, amountIn) returns (uint256 tokenIn_) {}
        catch Error(string memory) {
            // HSPOST
            assertTrue(false, NR_QUOTE_A);
        }
    }

    function quoteExactOutput(uint256 amountOut, bool dir) external eulerSwapDeployed {
        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);

        try periphery.quoteExactOutput(address(eulerSwap), tokenIn, tokenOut, amountOut) returns (uint256 tokenOut_) {}
        catch Error(string memory) {
            // HSPOST
            assertTrue(false, NR_QUOTE_B);
        }
    }

    // getLimits //TODO
}
