// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "forge-std/Test.sol";
import "forge-std/console.sol";

// Contracts
import {Invariants} from "./Invariants.t.sol";
import {Setup} from "./Setup.t.sol";

/*
 * Test suite that converts from  "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract CryticToFoundry is Invariants, Setup {
    bool internal IS_TEST = true;

    CryticToFoundry Tester = this;

    modifier setup() override {
        _;
    }

    function setUp() public {
        // Deploy protocol contracts
        _setUp(Curve.EULER_SWAP);

        // Initialize handler contracts
        _setUpHandlers();

        // Initialize hook contracts
        _setUpHooks();

        /// @dev fixes the actor to the first user
        actor = actors[USER1];

        vm.warp(101007);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  POSTCONDITIONS REPLAY                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_replaySwap() public {
        Tester.mint(2000000, 0, 0);
        Tester.swap(1, 0, 0, 0, 0); //@audit-issue is possible to extract value from the protocol 1 wei of value
    }

    function test_replay_swap() public {
        Tester.swap(0, 1, 0, 0, 0); //@audit-issue is possible to extract value from the protocol 1 wei of value -> rounding down on fx and fy functions fx(y) == fx(y-1) -> HSPOST_SWAP_A
    }

    function test_replay_nav() public {
        //@audit-issue when price changes user lp looses nav after a trade
        Tester.setPrice(1, 0.1 ether);
        Tester.swap(10, 0, 0, 10, 0);
    }

    function test_replay_roundtripswap() public {
        Tester.donateUnderlying(300000000000, 0);
        Tester.roundtripSwap(100000000, 0); // @audit-issue user receives the amount donated -> HSPOST_SWAP_B
    }

    function test_replay_swap_roundtripswap() public {
        //@audit-issue user gets 1 wei more one the swap back -> HSPOST_SWAP_B
        Tester.swap(15167520363383348756138763841789458381, 16455119106352766170018672268887607023990, 2, 0, 0);
        Tester.roundtripSwap(200000000, 0);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     INVARIANTS REPLAY                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 BROKEN INVARIANTS REPLAY                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Fast forward the time and set up an actor,
    /// @dev Use for ECHIDNA call-traces
    function _delay(uint256 _seconds) internal {
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up an actor
    function _setUpActor(address _origin) internal {
        actor = actors[_origin];
    }

    /// @notice Set up an actor and fast forward the time
    /// @dev Use for ECHIDNA call-traces
    function _setUpActorAndDelay(address _origin, uint256 _seconds) internal {
        actor = actors[_origin];
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up a specific block and actor
    function _setUpBlockAndActor(uint256 _block, address _user) internal {
        vm.roll(_block);
        actor = actors[_user];
    }

    /// @notice Set up a specific timestamp and actor
    function _setUpTimestampAndActor(uint256 _timestamp, address _user) internal {
        vm.warp(_timestamp);
        actor = actors[_user];
    }
}
