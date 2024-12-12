// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {MaglevBase} from "./MaglevBase.sol";

contract MaglevConstantSum is MaglevBase {
    error KNotSatisfied();

    uint64 public fee;
    uint96 public priceA;
    uint96 public priceB;

    struct ConstantSumParams {
        uint64 fee;
        uint96 priceA;
        uint96 priceB;
    }

    constructor(BaseParams memory baseParams, ConstantSumParams memory params) MaglevBase(baseParams) {
        setConstantSumParams(params);
    }

    function setConstantSumParams(ConstantSumParams memory params) public onlyOwner {
        fee = params.fee;
        priceA = params.priceA;
        priceB = params.priceB;
    }

    function k(uint256 r0, uint256 r1) public view returns (uint256) {
        return (r0 * priceA) + (r1 * priceB);
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

    // FIXME: incorporate priceA and priceB

    function computeQuote(uint256 amount, bool exactIn, bool) internal view virtual override returns (uint256) {
        if (exactIn) {
            return amount * (1e18 - fee) / 1e18;
        } else {
            return amount * 1e18 / (1e18 - fee);
        }
    }
}
