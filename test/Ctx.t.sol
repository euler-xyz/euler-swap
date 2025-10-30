// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapManagement, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {EulerSwapBase} from "../src/EulerSwapBase.sol";
import {CtxLib} from "../src/libraries/CtxLib.sol";

contract CtxTest is EulerSwapTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function storageLoc(bytes memory name) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(name)) - 1);
    }

    function test_staticCtxStorage() public pure {
        assertEq(CtxLib.CtxStateLocation, storageLoc("eulerSwap.state"));
        assertEq(CtxLib.CtxDynamicParamsLocation, storageLoc("eulerSwap.dynamicParams"));
    }

    function test_staticParamSize() public view {
        (IEulerSwap.StaticParams memory sParams,) =
            getEulerSwapParams(1e18, 1e18, 1e18, 1e18, 0.4e18, 0.85e18, 0, address(0));
        assertEq(abi.encode(sParams).length, 192);
    }

    function test_insufficientCalldata() public {
        // Proxy appends calldata, so you can't call directly without this

        vm.expectRevert(CtxLib.InsufficientCalldata.selector);
        EulerSwap(eulerSwapImpl).getStaticParams();
    }

    function test_callImplementationDirectly() public {
        // Underlying implementation is locked: must call via a proxy

        bool success;
        IEulerSwap.DynamicParams memory dParams;

        vm.expectRevert(EulerSwapManagement.AlreadyActivated.selector);
        (success,) = eulerSwapImpl.call(
            padCalldata(
                abi.encodeCall(EulerSwap.activate, (dParams, IEulerSwap.InitialState({reserve0: 1e18, reserve1: 1e18})))
            )
        );

        vm.expectRevert(EulerSwapBase.Locked.selector);
        (success,) = eulerSwapImpl.call(padCalldata(abi.encodeCall(EulerSwap.getReserves, ())));
    }

    function padCalldata(bytes memory inp) internal pure returns (bytes memory) {
        IEulerSwap.StaticParams memory sParams;
        return abi.encodePacked(inp, abi.encode(sParams));
    }
}
