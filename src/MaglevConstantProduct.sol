// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {MaglevBase} from "./MaglevBase.sol";

contract MaglevConstantProduct is MaglevBase {
    error KNotSatisfied();

    uint64 public fee;

    struct ConstantProductParams {
        uint64 fee;
    }

    constructor(BaseParams memory baseParams, ConstantProductParams memory params) MaglevBase(baseParams) {
        setConstantProductParams(params);
    }

    function setConstantProductParams(ConstantProductParams memory params) public onlyOwner {
        fee = params.fee;
    }

    function k(uint256 r0, uint256 r1) public pure returns (uint256) {
        return r0 * r1;
    }

    function verify(uint256 amount0In, uint256 amount1In, uint256 newReserve0, uint256 newReserve1)
        internal
        view
        virtual
        override
    {
        uint256 kBefore = k(reserve0, reserve1);
        uint256 kAfter = k(newReserve0 - (amount0In * fee / 1e18), newReserve1 - (amount1In * fee / 1e18));
        require(kAfter >= kBefore, KNotSatisfied());
    }

    function computeQuote(uint256 amount, bool exactIn, bool asset0IsInput)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        uint256 reserveIn = asset0IsInput ? reserve0 : reserve1;
        uint256 reserveOut = asset0IsInput ? reserve1 : reserve0;

        if (exactIn) {
            return (reserveOut * amount) / (reserveIn + amount) * (1e18 - fee) / 1e18;
        } else {
            return (reserveIn * amount) / (reserveOut - amount) * 1e18 / (1e18 - fee);
        }
    }
}
