// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

library CtxLib {
    struct Storage {
        uint112 reserve0;
        uint112 reserve1;
        uint32 status; // 0 = unactivated, 1 = unlocked, 2 = locked
    }

    // keccak256("eulerSwap.storage")
    bytes32 internal constant CtxStorageLocation = 0xae890085f98619e96ae34ba28d74baa4a4f79785b58fd4afcd3dc0338b79df91;

    function getStorage() internal pure returns (Storage storage s) {
        assembly {
            s.slot := CtxStorageLocation
        }
    }

    error InsufficientCalldata();

    /// @dev Unpacks encoded Params from trailing calldata. Loosely based on
    /// the implementation from EIP-3448 (except length is hard-coded).
    /// 384 is the size of the Params struct after ABI encoding.
    function getParams() internal pure returns (IEulerSwap.Params memory p) {
        require(msg.data.length >= 384, InsufficientCalldata());
        unchecked {
            return abi.decode(msg.data[msg.data.length - 384:], (IEulerSwap.Params));
        }
    }
}
