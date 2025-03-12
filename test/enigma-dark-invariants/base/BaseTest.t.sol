// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IEulerSwap} from "src/interfaces/IEulerSwap.sol";

// Libraries
import {Vm} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

// Utils
import {Actor} from "../utils/Actor.sol";
import {PropertiesConstants} from "../utils/PropertiesConstants.sol";
import {StdAsserts} from "../utils/StdAsserts.sol";
import {CoverageChecker} from "../utils/CoverageChecker.sol";

// Contracts
import {EulerSwap} from "src/EulerSwap.sol";

// Base
import {BaseStorage} from "./BaseStorage.t.sol";

import "forge-std/console.sol";

/// @notice Base contract for all test contracts extends BaseStorage
/// @dev Provides setup modifier and cheat code setup
/// @dev inherits Storage, Testing constants assertions and utils needed for testing
abstract contract BaseTest is BaseStorage, PropertiesConstants, StdAsserts, StdUtils, CoverageChecker {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   ACTOR PROXY MECHANISM                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Actor proxy mechanism
    modifier setup() virtual {
        actor = actors[msg.sender];
        targetActor = address(actor);
        _;
        actor = Actor(payable(address(0)));
        targetActor = address(0);
    }

    /// @dev Solves medusa backward time warp issue
    modifier monotonicTimestamp() virtual {
        // Implement monotonic timestamp if needed
        _;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          STRUCTS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     CHEAT CODE SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    /// @dev Virtual machine instance
    Vm internal constant vm = Vm(VM_ADDRESS);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _setTargetActor(address user) internal {
        targetActor = user;
    }

    /// @notice Get a random address
    function _makeAddr(string memory name) internal pure returns (address addr) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
    }

    /// @notice Helper function to deploy a contract from bytecode
    function deployFromBytecode(bytes memory bytecode) internal returns (address child) {
        assembly {
            child := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    /// @notice Helper function to approve an amount of tokens to a spender, a proxy Actor
    function _approve(address token, Actor actor_, address spender, uint256 amount) internal {
        bool success;
        bytes memory returnData;
        (success, returnData) = actor_.proxy(token, abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(success, string(returnData));
    }

    /// @notice Helper function to safely approve an amount of tokens to a spender

    function _approve(address token, address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        _safeApprove(token, spender, 0);
        vm.prank(owner);
        _safeApprove(token, spender, amount);
    }

    /// @notice Helper function to safely approve an amount of tokens to a spender
    /// @dev This function is used to revert on failed approvals
    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory retdata) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        assert(success);
        if (retdata.length > 0) assert(abi.decode(retdata, (bool)));
    }

    function _transferByActor(address token, address to, uint256 amount) internal {
        bool success;
        bytes memory returnData;
        (success, returnData) = actor.proxy(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success, string(returnData));
    }

    function _setupActorApprovals(address[] memory tokens, address[] memory contracts_) internal {
        for (uint256 i; i < actorAddresses.length; i++) {
            for (uint256 j; j < tokens.length; j++) {
                for (uint256 k; k < contracts_.length; k++) {
                    _approve(tokens[j], actorAddresses[i], contracts_[k], type(uint256).max);
                }
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                EULER-SWAP SPECIFIC HELPERS                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _getHolderNAV() internal view returns (int256) {
        uint256 balance0 = eTST.convertToAssets(eTST.balanceOf(holder));
        uint256 debt0 = eTST.debtOf(holder);
        uint256 balance1 = eTST2.convertToAssets(eTST2.balanceOf(holder));
        uint256 debt1 = eTST2.debtOf(holder);

        uint256 balValue = oracle.getQuote(balance0, address(assetTST), unitOfAccount)
            + oracle.getQuote(balance1, address(assetTST2), unitOfAccount);
        uint256 debtValue = oracle.getQuote(debt0, address(assetTST), unitOfAccount)
            + oracle.getQuote(debt1, address(assetTST2), unitOfAccount);

        return int256(balValue) - int256(debtValue);
    }

    function _createEulerSwap( // TODO should we deploy from the factory instead?
    uint112 debtLimitA, uint112 debtLimitB, uint256 fee, uint256 px, uint256 py, uint256 cx, uint256 cy)
        internal
    {
        eulerSwap = new EulerSwap(
            _getEulerSwapParams(debtLimitA, debtLimitB, fee),
            IEulerSwap.CurveParams({priceX: px, priceY: py, concentrationX: cx, concentrationY: cy})
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), true);
    }

    function _getEulerSwapParams(uint112 reserve0, uint112 reserve1, uint256 fee)
        internal
        view
        returns (EulerSwap.Params memory)
    {
        return IEulerSwap.Params({
            vault0: address(eTST),
            vault1: address(eTST2),
            eulerAccount: holder,
            equilibriumReserve0: reserve0,
            equilibriumReserve1: reserve1,
            currReserve0: reserve0,
            currReserve1: reserve1,
            fee: fee
        });
    }
}
