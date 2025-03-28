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

        /// @dev HSPOST_SWAP_A

        assertGe(defaultVarsAfter.holderNAV, defaultVarsBefore.holderNAV, HSPOST_SWAP_A);

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

        /// @dev HSPOST_DEBT_A
        assertLe(defaultVarsAfter.holderETSTDebt, eulerSwap.reserve0(), HSPOST_DEBT_A);
        assertLe(defaultVarsAfter.holderETST2Debt, eulerSwap.reserve1(), HSPOST_DEBT_A);
        assertLe(defaultVarsAfter.holderETSTDebt, eulerSwap.reserve1(), HSPOST_DEBT_A);
        assertLe(defaultVarsAfter.holderETST2Debt, eulerSwap.reserve0(), HSPOST_DEBT_A);
    }
}
