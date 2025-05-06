// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {CtxLib} from "../src/libraries/CtxLib.sol";

contract CtxTest is EulerSwapTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_staticCtxStorage() public pure {
        assertEq(CtxLib.CtxStorageLocation, keccak256("eulerSwap.storage"));
    }

    function test_staticParamSize() public view {
        IEulerSwap.Params memory params = getEulerSwapParams(1e18, 1e18, 1e18, 1e18, 0.4e18, 0.85e18, 0, 0, address(0));
        assertEq(abi.encode(params).length, 384);
    }

    function test_insufficientCalldata() public {
        // Proxy appends 384 bytes of calldata, so you can't call directly without this

        vm.expectRevert(CtxLib.InsufficientCalldata.selector);
        EulerSwap(eulerSwapImpl).getParams();
    }

    function test_callImplementationDirectly() public {
        // Underlying implementation is locked: must call via a proxy

        bool success;

        vm.expectRevert(EulerSwap.AlreadyActivated.selector);
        (success,) = eulerSwapImpl.call(
            padCalldata(
                abi.encodeCall(EulerSwap.activate, (IEulerSwap.InitialState({currReserve0: 1e18, currReserve1: 1e18})))
            )
        );

        vm.expectRevert(EulerSwap.Locked.selector);
        (success,) = eulerSwapImpl.call(padCalldata(abi.encodeCall(EulerSwap.getReserves, ())));
    }

    function padCalldata(bytes memory inp) internal pure returns (bytes memory) {
        IEulerSwap.Params memory params;
        return abi.encodePacked(inp, abi.encode(params));
    }
}
