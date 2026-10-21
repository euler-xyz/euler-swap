// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IEulerSwap} from "src/interfaces/IEulerSwap.sol";

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
    CryticToFoundry Tester = this;

    modifier setup() override {
        _;
    }

    function setUp() public {
        // Deploy protocol contracts
        _setUp();

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

    /*     function test_replay_swap() public {
        //@audit-issue is possible to extract value from the protocol 1 wei of value
        Tester.setupMaglev(10, 50e18, 50e18, 0, Curve(0), MaglevEulerSwap.EulerSwapParams(1e18, 1e18, 0.4e18, 0.85e18));
        Tester.mint(2000000, 0, 0);
        Tester.swap(1, 0, 0, 0, 0);
    }

    function test_replay_nav() public {
        //@audit-issue when price changes user lp looses nav after a trade
        Tester.setupMaglev(10, 50e18, 50e18, 0, Curve(0), MaglevEulerSwap.EulerSwapParams(1e18, 1e18, 0.4e18, 0.85e18));
        Tester.setPrice(1, 0.1 ether);
        Tester.swap(10, 0, 0, 10, 0);
    }

    function test_replay_roundtripswap() public {
        // @audit-ok user receives the amount donated -> HSPOST_SWAP_B -> expected functionality
        Tester.setupMaglev(10, 50e18, 50e18, 0, Curve(0), MaglevEulerSwap.EulerSwapParams(1e18, 1e18, 0.4e18, 0.85e18));
        Tester.donateUnderlying(300000000000, 0);
        Tester.roundtripSwap(100000000, 0);
    }

    function test_replay_2roundtripswap() public {
        //@audit-issue user gets 1 wei more one the swap back -> HSPOST_SWAP_B
        Tester.setupMaglev(10, 50e18, 50e18, 0, Curve(0), MaglevEulerSwap.EulerSwapParams(1e18, 1e18, 0.4e18, 0.85e18));
        Tester.swap(1516752036338334875613876384, 1645511910635276617001867226888, 2, 0, 0);
        Tester.roundtripSwap(200000000, 0);
    } */

    /*     function test_replay_setupEulerSwap() public {
        //@audit-ok fixed by clamping fee
        Tester.setupEulerSwap(
            0,
            0,
            0,
            1003720677821071739,
            IEulerSwap.CurveParams(
                0, 12246676942863640986141097041882032371945, 31951643412123143093714293698540253070340823296393767, 0
            )
        );
    }

    function test_replay_swapExactOut() public {
        //@audit-ok Invalid: 1!=0, reason: HSPOST_RESERVES_C: If amountIn tokenOut collateral, a specific amountOut is borrowed
        Tester.setupEulerSwap(0, 0, 0, 0, IEulerSwap.CurveParams(0, 0, 0, 0));
        Tester.swap(0, 0, 1, 0, 0);
        Tester.mint(1, 1, 0);
        Tester.redeem(115792089237316195423570985008687907853269984665640564039457584007913129639935, 0, 0);
        console.log("########################");
        console.log("debt2", eTST.debtOf(address(holder)));
        Tester.swapExactOut(0, 0, false);
    }

    function test_replay_swapExactIn() public {
        //@audit-ok Invalid: 1!=0, reason: HSPOST_RESERVES_C: If amountIn tokenOut collateral, a specific amountOut is borrowed
        Tester.setupEulerSwap(0, 0, 0, 0, IEulerSwap.CurveParams(0, 0, 0, 0));
        Tester.mint(1, 1, 0);
        Tester.redeem(115792089237316195423570985008687907853269984665640564039457584007913129639935, 0, 0);
        Tester.donateUnderlying(2, 1);
        Tester.swapExactIn(0, 0, true);
    } */

    /*     function test_replay_swap() public {
        //@audit-ok Invalid: 1!=0, reason: HSPOST_RESERVES_A: If there is debt in tokenIn, the debt must be repaid
        Tester.setupEulerSwap(0, 0, 0, 0, IEulerSwap.CurveParams(0, 0, 0, 0));
        Tester.redeem(115792089237316195423570985008687907853269984665640564039457584007913129639935, 0, 1);
        Tester.mint(1, 1, 1);
        console.log("########################");
        console.log("debt2", eTST2.debtOf(address(holder)));
        console.log("balance2", eTST2.balanceOf(address(holder)));
        Tester.swap(0, 1, 2, 0, 0);
    } */

    function test_replay_roundtripSwap() public {
        //@audit Invalid: 1999999999999999999999<2000000000000000000000 failed, reason: HSPOST_SWAP_A: Holder's NAV should increase monotonically
        Tester.setupEulerSwap(0, 0, 0, 0, IEulerSwap.CurveParams(2069895513206400, 0, 0, 77696590));
        Tester.roundtripSwap(1, 0);
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
