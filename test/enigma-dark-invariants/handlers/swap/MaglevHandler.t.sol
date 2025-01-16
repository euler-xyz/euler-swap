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

    function swap(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In, uint8 i) public  setup maglevDeployed  {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        receiver = roundtripSwapActor == address(0) ? _getRandomActor(i) : roundtripSwapActor;

        address target = address(maglev);

        //if (amount0Out >= 2 ether && amount1In >= 10 ether) assert(false);

        //require(amount0Out > 1 ether || amount1Out > 1 ether, "MaglevHandler: Invalid amount out");

        if (amount0In > 0) {
            _transferByActor(address(assetTST), address(maglev), amount0In);
        }

        if (amount1In > 0) {
            _transferByActor(address(assetTST2), address(maglev), amount1In);
        }

        _before();
        (success, returnData) =
            actor.proxy(target, abi.encodeWithSelector(IMaglevBase.swap.selector, amount0Out, amount1Out, receiver, ""));

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

            //assert((amount0Out > 1 && amount1In > 1) || (amount1Out > 1 && amount0In > 1));

            _checkCoverage(amount0Out, 0, type(uint256).max);
        } else {
            revert("MaglevHandler: swap failed");
        }

        delete receiver;
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

        swap(amount0Out, amount1Out, amount0In, amount1In, 0);

        // SWAP 2

        if (i % 2 == 0) {
            // token0 -> token1 case
            amount1In = amount1Out;
            amount0Out = maglev.quoteExactInput(address(assetTST2), address(assetTST), amount1In);
            delete amount1Out; // @audit seems like input amounts are kinda delayed check uniswap v2
            delete amount0In;
        } else {
            // token1 -> token0 case
            amount0In = amount0Out;
            amount1Out = maglev.quoteExactInput(address(assetTST), address(assetTST2), amount0In);
            delete amount0Out;
            delete amount1In;
        }

        swap(amount0Out, amount1Out, amount0In, amount1In, 0);

        uint256 actorInBalanceAfter = assetTSTIn.balanceOf(roundtripSwapActor);

        // HSPOST
        //assertLe(actorInBalanceAfter, actorInBalanceBefore, HSPOST_SWAP_B);
    }

    function quoteExactInput(uint256 amountIn, bool dir) external {
        (address assetIn, address assetOut) = _getAssetsByDir(dir);

        try maglev.quoteExactInput(assetIn, assetOut, amountIn) returns (uint256 amountOut) {}
        catch Error(string memory) {
            // HSPOST
            assertTrue(false, NR_QUOTE_A);
        }
    }

    function quoteExactOutput(uint256 amountIn, bool dir) external {
        (address assetIn, address assetOut) = _getAssetsByDir(dir);

        try maglev.quoteExactOutput(assetIn, assetOut, amountIn) returns (uint256 amountOut) {}
        catch Error(string memory) {
            // HSPOST
            assertTrue(false, NR_QUOTE_B);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HSPOST: SWAP                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Postconditions common to all three curves
    function _commonPostconditions(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In)
        internal
    {
        /// @dev HSPOST_SWAP_C

        if (amount0Out > 0) {
            assertEq(
                defaultVarsAfter.users[receiver].assetTSTBalance,
                defaultVarsBefore.users[receiver].assetTSTBalance + amount0Out,
                HSPOST_SWAP_C
            );
        }

        if (amount1Out > 0) {
            assertEq(
                defaultVarsAfter.users[receiver].assetTST2Balance,
                defaultVarsBefore.users[receiver].assetTST2Balance + amount1Out,
                HSPOST_SWAP_C
            );
        }

        //assertGe(defaultVarsAfter.holderNAV, defaultVarsBefore.holderNAV, HSPOST_SWAP_A);// TODO remove + 1 when rounding is fixed

        /// @dev HSPOST_RESERVES_A

        if (amount0In < defaultVarsBefore.holderETSTDebt) {
            assertEq(defaultVarsAfter.holderETSTDebt, defaultVarsBefore.holderETSTDebt - amount0In, HSPOST_SWAP_B);
        } else {
            assertEq(defaultVarsAfter.holderETSTDebt, 0, HSPOST_RESERVES_A);
        }

        if (amount1In < defaultVarsBefore.holderETST2Debt) {
            assertEq(defaultVarsAfter.holderETST2Debt, defaultVarsBefore.holderETST2Debt - amount1In, HSPOST_SWAP_B);
        } else {
            assertEq(defaultVarsAfter.holderETST2Debt, 0, HSPOST_RESERVES_A);
        }

        /// @dev HSPOST_RESERVES_B

        if (amount0Out < defaultVarsBefore.holderETSTAssets) {
            assertEq(
                defaultVarsAfter.holderETSTAssets, defaultVarsBefore.holderETSTAssets - amount0Out, HSPOST_RESERVES_B
            );
        } else {
            assertEq(defaultVarsAfter.holderETSTAssets, 0, HSPOST_RESERVES_B);
            assertEq(
                defaultVarsAfter.holderETSTDebt, amount0Out - defaultVarsBefore.holderETSTAssets, HSPOST_RESERVES_C
            );
        }

        if (amount1Out < defaultVarsBefore.holderETST2Assets) {
            assertEq(
                defaultVarsAfter.holderETST2Assets, defaultVarsBefore.holderETST2Assets - amount1Out, HSPOST_RESERVES_B
            );
        } else {
            assertEq(defaultVarsAfter.holderETST2Assets, 0, HSPOST_RESERVES_B);
            assertEq(
                defaultVarsAfter.holderETST2Debt, amount1Out - defaultVarsBefore.holderETST2Assets, HSPOST_RESERVES_C
            );
        }
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
