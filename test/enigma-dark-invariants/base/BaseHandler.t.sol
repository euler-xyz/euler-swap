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

    function _getAssetsByDir(bool dir) internal view returns (address assetIn, address assetOut) {
        return dir ? (address(assetTST), address(assetTST2)) : (address(assetTST2), address(assetTST));
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
    function _mint(address token, address receiver, uint256 amount) internal {
        TestERC20(token).mint(receiver, amount);
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
}
