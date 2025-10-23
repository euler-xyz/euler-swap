// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

library CtxLib {
    struct State {
        uint112 reserve0;
        uint112 reserve1;
        uint32 status; // 0 = unactivated, 1 = unlocked, 2 = locked
        mapping(address manager => bool installed) managers;
    }

    // keccak256("eulerSwap.state") - 1
    bytes32 internal constant CtxStateLocation = 0x10ee9b31f73104ff2cf413742414a498e1f7b56c11cb512bca58a9c50727bb58;

    function getState() internal pure returns (State storage s) {
        assembly {
            s.slot := CtxStateLocation
        }
    }

    // keccak256("eulerSwap.dynamicParams") - 1
    bytes32 internal constant CtxDynamicParamsLocation =
        0xca4da3477ca592c011a91679daaaf19e95f02a3a91537965b17e4113575fb219;

    function writeDynamicParamsToStorage(IEulerSwap.DynamicParams memory dParams) internal {
        IEulerSwap.DynamicParams storage s;

        assembly {
            s.slot := CtxDynamicParamsLocation
        }

        s.equilibriumReserve0 = dParams.equilibriumReserve0;
        s.equilibriumReserve1 = dParams.equilibriumReserve1;
        s.minReserve0 = dParams.minReserve0;
        s.minReserve1 = dParams.minReserve1;
        s.priceX = dParams.priceX;
        s.priceY = dParams.priceY;
        s.concentrationX = dParams.concentrationX;
        s.concentrationY = dParams.concentrationY;
        s.fee0 = dParams.fee0;
        s.fee1 = dParams.fee1;
        s.expiration = dParams.expiration;
        s.swapHookedOperations = dParams.swapHookedOperations;
        s.swapHook = dParams.swapHook;
    }

    function getDynamicParams() internal pure returns (IEulerSwap.DynamicParams memory) {
        IEulerSwap.DynamicParams storage s;

        assembly {
            s.slot := CtxDynamicParamsLocation
        }

        return s;
    }

    error InsufficientCalldata();

    /// @dev Unpacks encoded Params from trailing calldata. Loosely based on
    /// the implementation from EIP-3448 (except length is hard-coded).
    /// 192 is the size of the StaticParams struct after ABI encoding.
    function getStaticParams() internal pure returns (IEulerSwap.StaticParams memory p) {
        require(msg.data.length >= 192, InsufficientCalldata());
        unchecked {
            return abi.decode(msg.data[msg.data.length - 192:], (IEulerSwap.StaticParams));
        }
    }
}
