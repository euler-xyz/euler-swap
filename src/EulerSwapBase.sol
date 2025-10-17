// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {EVCUtil} from "evc/utils/EVCUtil.sol";

import {CtxLib} from "./libraries/CtxLib.sol";

abstract contract EulerSwapBase is EVCUtil {
    error Locked();

    constructor(address evc_) EVCUtil(evc_) {
        CtxLib.State storage s = CtxLib.getState();
        s.status = 2; // can only be used via delegatecall proxy
    }

    modifier nonReentrant() {
        CtxLib.State storage s = CtxLib.getState();
        require(s.status == 1, Locked());
        s.status = 2;

        _;

        s.status = 1;
    }

    modifier nonReentrantView() {
        CtxLib.State storage s = CtxLib.getState();
        require(s.status != 2, Locked());

        _;
    }
}
