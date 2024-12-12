// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {console} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MaglevBase} from "./MaglevBase.sol";

contract MaglevEulerSwap is MaglevBase {
    error KNotSatisfied();
    error ReservesZero();
    error InvalidInputCoordinate();

    uint256 public px;
    uint256 public py;
    uint256 public cx;
    uint256 public cy;
    uint256 public fee;

    struct EulerSwapParams {
        uint256 px;
        uint256 py;
        uint256 cx;
        uint256 cy;
        uint256 fee;
    }

    constructor(BaseParams memory _baseParams, EulerSwapParams memory _params) MaglevBase(_baseParams) {
        setEulerSwapParams(_params);
    }

    function setEulerSwapParams(EulerSwapParams memory _params) public onlyOwner {
        px = _params.px;
        py = _params.py;
        cx = _params.cx;
        cy = _params.cy;
        fee = 1e18 + _params.fee;
        //fee = Math.max(1e18 + _params.fee, 1.0000000000001e18); // minimum fee required to compensate for rounding
    }

    // FIXME: how to charge fees?
    function verify(uint256, uint256, uint256 _newReserve0, uint256 _newReserve1) internal view virtual override {
        int256 delta = 0;

        if (_newReserve0 >= initialReserve0) {
            delta = int256(_newReserve0) - int256(fy(_newReserve1, px, py, initialReserve0, initialReserve1, cx, cy));
        } else {
            delta = int256(_newReserve1) - int256(fx(_newReserve0, px, py, initialReserve0, initialReserve1, cx, cy));
        }

        // if delta is >= zero, then point is on or above the curve
        require(delta >= 0, KNotSatisfied());
    }

    function computeQuote(uint256 _amount, bool _exactIn, bool _asset0IsInput)
        internal
        view
        virtual
        override
        returns (uint256 output)
    {
        int256 dx;
        int256 dy;

        if (_exactIn) {
            if (_asset0IsInput) dx = int256(_amount);
            else dy = int256(_amount);
        } else {
            if (_asset0IsInput) dy = -int256(_amount);
            else dx = -int256(_amount);
        }

        {
            int256 reserve0New = int256(uint256(reserve0));
            int256 reserve1New = int256(uint256(reserve1));

            if (dx != 0) {
                reserve0New += dx;
                reserve1New = int256(fx(uint256(reserve0New), px, py, initialReserve0, initialReserve1, cx, cy));
            }
            if (dy != 0) {
                reserve1New += dy;
                reserve0New = int256(fy(uint256(reserve1New), px, py, initialReserve0, initialReserve1, cx, cy));
            }

            dx = reserve0New - int256(uint256(reserve0));
            dy = reserve1New - int256(uint256(reserve1));
        }

        if (_exactIn) {
            if (_asset0IsInput) output = uint256(-dy);
            else output = uint256(-dx);
            output = output * 1e18 / fee;
        } else {
            if (_asset0IsInput) output = uint256(dx);
            else output = uint256(dy);
            output = output * fee / 1e18;
        }
    }

    ///// Curve math routines

    function fx(uint256 _xt, uint256 _px, uint256 _py, uint256 _x0, uint256 _y0, uint256 _cx, uint256 _cy)
        internal
        pure
        returns (uint256)
    {
        require(_xt > 0, ReservesZero());
        if (_xt <= _x0) {
            return fx1(_xt, _px, _py, _x0, _y0, _cx, _cy);
        } else {
            return fx2(_xt, _px, _py, _x0, _y0, _cx, _cy);
        }
    }

    function fy(uint256 _yt, uint256 _px, uint256 _py, uint256 _x0, uint256 _y0, uint256 _cx, uint256 _cy)
        internal
        pure
        returns (uint256)
    {
        require(_yt > 0, ReservesZero());
        if (_yt <= _y0) {
            return fx1(_yt, _py, _px, _y0, _x0, _cy, _cx);
        } else {
            return fx2(_yt, _py, _px, _y0, _x0, _cy, _cx);
        }
    }

    function fx1(uint256 _xt, uint256 _px, uint256 _py, uint256 _x0, uint256 _y0, uint256 _cx, uint256)
        internal
        pure
        returns (uint256)
    {
        require(_xt <= _x0, InvalidInputCoordinate());
        return
            _y0 + _px * 1e18 / _py * (_cx * (2 * _x0 - _xt) / 1e18 + (1e18 - _cx) * _x0 / 1e18 * _x0 / _xt - _x0) / 1e18;
    }

    function fx2(uint256 _xt, uint256 _px, uint256 _py, uint256 _x0, uint256 _y0, uint256, uint256 _cy)
        internal
        pure
        returns (uint256)
    {
        require(_xt > _x0, InvalidInputCoordinate());
        // intermediate values for solving quadratic equation
        uint256 a = _cy;
        int256 b = (int256(_px) * 1e18 / int256(_py)) * (int256(_xt) - int256(_x0)) / 1e18
            + int256(_y0) * (1e18 - 2 * int256(_cy)) / 1e18;
        int256 c = (int256(_cy) - 1e18) * int256(_y0) ** 2 / 1e18 / 1e18;
        uint256 discriminant = uint256(int256(uint256(b ** 2)) - 4 * int256(a) * int256(c));
        uint256 numerator = uint256(-b + int256(uint256(Math.sqrt(discriminant))));
        uint256 denominator = 2 * a;
        return numerator * 1e18 / denominator;
    }
}
