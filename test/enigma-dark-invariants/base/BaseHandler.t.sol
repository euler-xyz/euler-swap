// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces

// Libraries
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {TestERC20} from "../utils/mocks/TestERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Contracts
import {Actor} from "../utils/Actor.sol";
import {HookAggregator} from "../hooks/HookAggregator.t.sol";

import "forge-std/console.sol";

/// @title BaseHandler
/// @notice Contains common logic for all handlers
/// @dev inherits all suite assertions since per action assertions are implmenteds in the handlers
contract BaseHandler is HookAggregator {
    using EnumerableSet for EnumerableSet.UintSet;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    address receiver;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         MODIFIERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    modifier eulerSwapNotDeployed() {
        if (address(eulerSwap) != address(0)) revert("BaseHandler: EulerSwap already deployed on this trace");
        _;
    }

    modifier eulerSwapDeployed() {
        if (address(eulerSwap) == address(0)) revert("BaseHandler: EulerSwap has not been deployed on this trace");
        _;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       SHARED VARAIBLES                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // ERC4626

    /// @notice Track of the total amount borrowed
    uint256 internal ghost_totalBorrowed;

    /// @notice Track of the total amount borrowed per user
    mapping(address => uint256) internal ghost_owedAmountPerUser;

    /// @notice Track the enabled collaterals per user
    mapping(address => EnumerableSet.AddressSet) internal ghost_accountCollaterals;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   HELPERS: RANDOM GETTERS                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Get a random asset address
    function _getRandomBaseAsset(uint256 _i) internal view returns (address) {
        uint256 _assetIndex = _i % baseAssets.length;
        return baseAssets[_assetIndex];
    }

    /// @notice Get a random actor proxy address
    function _getRandomActor(uint256 _i) internal view returns (address) {
        uint256 _actorIndex = _i % NUMBER_OF_ACTORS;
        return actorAddresses[_actorIndex];
    }

    /// @notice Get a random vault address
    function _getRandomVault(uint8 i) internal view returns (address) {
        uint256 _vaultIndex = i % vaults.length;
        return vaults[_vaultIndex];
    }

    function _getAssetsByDir(bool dir) internal view returns (address asset0, address asset1) {
        asset0 = eulerSwap.asset0();
        asset1 = eulerSwap.asset1();
        return dir ? (asset0, asset1) : (asset1, asset0);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                             HELPERS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Helper function to randomize a uint256 seed with a string salt
    function _randomize(uint256 seed, string memory salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, salt)));
    }

    /// @notice Helper function to get a random value
    function _getRandomValue(uint256 modulus) internal view returns (uint256) {
        uint256 randomNumber = uint256(keccak256(abi.encode(block.timestamp, block.prevrandao, msg.sender)));
        return randomNumber % modulus; // Adjust the modulus to the desired range
    }

    /// @notice Helper function to mint an amount of tokens to an address
    function _mint(address token, address receiver_, uint256 amount) internal {
        TestERC20(token).mint(receiver_, amount);
    }

    /// @notice Helper function to mint an amount of tokens to an address and approve them to a spender
    /// @param token Address of the token to mint
    /// @param owner Address of the new owner of the tokens
    /// @param spender Address of the spender to approve the tokens to
    /// @param amount Amount of tokens to mint and approve
    function _mintAndApprove(address token, address owner, address spender, uint256 amount) internal {
        _mint(token, owner, amount);
        _approve(token, owner, spender, amount);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HSPOST: SWAP                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Postconditions common to all three curves
    function _eulerSwapPostconditions(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In)
        internal
    {
        // SWAP POSTCONDITIONS

        assertGe(defaultVarsAfter.holderNAV, defaultVarsBefore.holderNAV, HSPOST_SWAP_A);

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

        // RESERVES POSTCONDITIONS

        int256 amount0Delta = int256(amount0In) - int256(amount0Out);
        int256 amount1Delta = int256(amount1In) - int256(amount1Out);

        /// asset0 (eTST)
        _checkAssetChanges(
            amount0Delta,
            defaultVarsBefore.holderETSTDebt,
            defaultVarsAfter.holderETSTDebt,
            defaultVarsBefore.holderETSTAssets,
            defaultVarsAfter.holderETSTAssets,
            "token0"
        );

        /// asset1 (eTST2)
        _checkAssetChanges(
            amount1Delta,
            defaultVarsBefore.holderETST2Debt,
            defaultVarsAfter.holderETST2Debt,
            defaultVarsBefore.holderETST2Assets,
            defaultVarsAfter.holderETST2Assets,
            "token1"
        );

        // DEBT POSTCONDITIONS

        assertLe(defaultVarsAfter.holderETSTDebt, eulerSwap.reserve0(), HSPOST_DEBT_A);
        assertLe(defaultVarsAfter.holderETST2Debt, eulerSwap.reserve1(), HSPOST_DEBT_A);
        assertLe(defaultVarsAfter.holderETSTDebt, eulerSwap.reserve1(), HSPOST_DEBT_A);
        assertLe(defaultVarsAfter.holderETST2Debt, eulerSwap.reserve0(), HSPOST_DEBT_A);
    }

    function _checkAssetChanges(
        int256 amountDelta,
        uint256 beforeDebt,
        uint256 afterDebt,
        uint256 beforeAssets,
        uint256 afterAssets,
        string memory tokenId
    ) internal {
        if (amountDelta > 0) {
            // Positive delta means repaying debt first, then possibly increasing assets
            if (uint256(amountDelta) < beforeDebt) {
                // Just reduce debt
                assertEq(
                    afterDebt, beforeDebt - uint256(amountDelta), string.concat(HSPOST_RESERVES_A, " for ", tokenId)
                );
            } else {
                // Debt is fully repaid
                assertEq(afterDebt, 0, string.concat(HSPOST_RESERVES_B, " for ", tokenId));

                // If there's excess after repaying debt, it should increase assets
                uint256 excess = uint256(amountDelta) - beforeDebt;
                if (excess > 0) {
                    assertEq(afterAssets, beforeAssets + excess, string.concat(HSPOST_RESERVES_C, " for ", tokenId));
                }
            }
        } else {
            // Negative delta means using assets first, then borrowing
            if (uint256(-amountDelta) < beforeAssets) {
                // Just reduce assets
                assertEq(
                    afterAssets,
                    beforeAssets - uint256(-amountDelta),
                    string.concat(HSPOST_RESERVES_D, " for ", tokenId)
                );
            } else {
                // Assets are depleted
                assertEq(afterAssets, 0, string.concat(HSPOST_RESERVES_E, " for ", tokenId));

                // Any deficit beyond available assets increases debt
                uint256 deficit = uint256(-amountDelta) - beforeAssets;
                assertEq(afterDebt - beforeDebt, deficit, string.concat(HSPOST_RESERVES_F, " for ", tokenId));
            }
        }
    }
}
