// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEulerSwap} from "src/interfaces/IEulerSwap.sol";

// Libraries
import "forge-std/console.sol";

// Test Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title EulerSwapHandler
/// @notice Handler test contract for a set of actions
abstract contract EulerSwapHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    address roundtripSwapActor;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTIONS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function activate() public setup eulerSwapDeployed {
        eulerSwap.activate();
    }

    function swap(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In, uint8 i)
        public
        setup
        eulerSwapDeployed
        skimAll
    {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        receiver = roundtripSwapActor == address(0) ? _getRandomActor(i) : roundtripSwapActor;

        address target = address(eulerSwap);

        //if (amount0Out >= 2 ether && amount1In >= 10 ether) assert(false);

        //require(amount0Out > 1 ether || amount1Out > 1 ether, "EulerSwapHandler: Invalid amount out");

        if (amount0In > 0) {
            _transferByActor(address(assetTST), address(eulerSwap), amount0In);
        }

        if (amount1In > 0) {
            _transferByActor(address(assetTST2), address(eulerSwap), amount1In);
        }

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IEulerSwap.swap.selector, amount0Out, amount1Out, receiver, ""));

        if (success) {
            _after();

            // POSTCONDITIONS
            _eulerSwapPostconditions(amount0Out, amount1Out, amount0In, amount1In);
        } else {
            revert("EulerSwapHandler: swap failed");
        }

        delete receiver;
    }

    function roundtripSwap(uint256 amount, uint8 i) external setup eulerSwapDeployed {
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
            amount1Out = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amount0In);
        } else {
            // token1 -> token0 case
            amount1In = amount;
            amount0Out = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amount1In);
        }

        swap(amount0Out, amount1Out, amount0In, amount1In, 0);

        // SWAP 2

        if (i % 2 == 0) {
            // token0 -> token1 case
            amount1In = amount1Out;
            amount0Out = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amount1In);
            delete amount1Out; // @audit seems like input amounts are kinda delayed check uniswap v2
            delete amount0In;
        } else {
            // token1 -> token0 case
            amount0In = amount0Out;
            amount1Out = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amount0In);
            delete amount0Out;
            delete amount1In;
        }

        swap(amount0Out, amount1Out, amount0In, amount1In, 0);

        uint256 actorInBalanceAfter = assetTSTIn.balanceOf(roundtripSwapActor);

        /// @dev HSPOST_SWAP_B
        assertLe(actorInBalanceAfter, actorInBalanceBefore, HSPOST_SWAP_B);
    }
}
