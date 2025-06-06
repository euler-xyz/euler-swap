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

    function swapExactIn(uint256 amountIn, uint256 amountOutMin, bool dir) public setup eulerSwapDeployed skimAll {
        bool success;
        receiver = address(actor);

        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);
        (uint256 tokenInLimit, uint256 tokenOutLimit) = periphery.getLimits(address(eulerSwap), tokenIn, tokenOut);

        address target = address(periphery);

        _before();
        (success,) = actor.proxy(
            target,
            abi.encodeWithSelector(
                IEulerSwapPeriphery.swapExactIn.selector, address(eulerSwap), tokenIn, tokenOut, amountIn, amountOutMin
            )
        );

        if (success) {
            _after();

            if (dir) {
                _eulerSwapPostconditions(0, amountOutMin, amountIn, 0);
            } else {
                _eulerSwapPostconditions(amountOutMin, 0, 0, amountIn);
            }

            // HSPOST
            assertLe(amountIn, tokenInLimit, HSPOST_SWAP_D);
            assertLe(amountOutMin, tokenOutLimit, HSPOST_SWAP_D);
        } else {
            revert("EulerSwapPeripheryHandler: swapExactIn failed");
        }

        delete receiver;
    }

    function swapExactOut(uint256 amountOut, uint256 amountInMax, bool dir) public setup eulerSwapDeployed skimAll {
        bool success;
        receiver = address(actor);

        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);
        (uint256 tokenInLimit, uint256 tokenOutLimit) = periphery.getLimits(address(eulerSwap), tokenIn, tokenOut);

        address target = address(periphery);

        _before();
        (success,) = actor.proxy(
            target,
            abi.encodeWithSelector(
                IEulerSwapPeriphery.swapExactOut.selector, address(eulerSwap), tokenIn, tokenOut, amountOut, amountInMax
            )
        );

        if (success) {
            _after();

            if (dir) {
                _eulerSwapPostconditions(0, amountOut, amountInMax, 0);
            } else {
                _eulerSwapPostconditions(amountOut, 0, 0, amountInMax);
            }

            // HSPOST
            assertLe(amountOut, tokenOutLimit, HSPOST_SWAP_D);
            assertLe(amountInMax, tokenInLimit, HSPOST_SWAP_D);
        } else {
            revert("EulerSwapPeripheryHandler: swapExactOut failed");
        }

        delete receiver;
    }

    function quoteExactInput(uint256 amountIn, bool dir) external setup eulerSwapDeployed {
        bool success;

        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);

        uint256 amountOutMin;

        try periphery.quoteExactInput(address(eulerSwap), tokenIn, tokenOut, amountIn) returns (uint256 amountOutMin_) {
            amountOutMin = amountOutMin_;

            if (amountIn > IERC20(tokenIn).balanceOf(address(actor))) {
                _mint(tokenIn, address(actor), amountIn);
            }
        } catch Error(string memory) {
            // HSPOST
            assertTrue(false, NR_QUOTE_A);
        }

        address target = address(periphery);

        _before();
        (success,) = actor.proxy(
            target,
            abi.encodeWithSelector(
                IEulerSwapPeriphery.swapExactIn.selector, address(eulerSwap), tokenIn, tokenOut, amountIn, amountOutMin
            )
        );
        _after();

        // HSPOST
        assertTrue(success, HSPOST_SWAP_E);
    }

    function quoteExactOutput(uint256 amountOut, bool dir) external setup eulerSwapDeployed {
        bool success;

        (address tokenIn, address tokenOut) = _getAssetsByDir(dir);

        uint256 amountInMax;

        try periphery.quoteExactOutput(address(eulerSwap), tokenIn, tokenOut, amountOut) returns (uint256 amountInMax_)
        {
            amountInMax = amountInMax_;

            if (amountInMax > IERC20(tokenIn).balanceOf(address(actor))) {
                _mint(tokenIn, address(actor), amountInMax);
            }
        } catch Error(string memory) {
            // HSPOST
            assertTrue(false, NR_QUOTE_B);
        }

        address target = address(periphery);

        _before();
        (success,) = actor.proxy(
            target,
            abi.encodeWithSelector(
                IEulerSwapPeriphery.swapExactOut.selector, address(eulerSwap), tokenIn, tokenOut, amountOut, amountInMax
            )
        );
        _after();

        // HSPOST
        assertTrue(success, HSPOST_SWAP_E);
    }
}
