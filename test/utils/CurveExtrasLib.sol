// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {CurveLib} from "../../src/libraries/CurveLib.sol";
import {IEulerSwap} from "../../src/interfaces/IEulerSwap.sol";

library CurveExtrasLib {
    /// @dev Calculates marginal price after a swap of `amount` either of `asset0` or `asset1`, depending on `asset0IsInput`
    /// @return price asset1\asset0 price in 1e18 scale
    function computeMarginalPriceAfterSwap(
        IEulerSwap.DynamicParams memory dParams,
        uint256 reserve0,
        uint256 reserve1,
        bool asset0IsInput,
        uint256 amount
    ) internal pure returns (uint256) {
        uint256 px = dParams.priceX;
        uint256 py = dParams.priceY;
        uint256 x0 = dParams.equilibriumReserve0;
        uint256 y0 = dParams.equilibriumReserve1;
        uint256 cx = dParams.concentrationX;
        uint256 cy = dParams.concentrationY;
        uint256 fee = dParams.fee0;

        amount = amount - (amount * fee / 1e18);

        int256 result;
        if (asset0IsInput) {
            // swap X in and Y out
            uint256 xNew = reserve0 + amount;

            if (xNew <= x0) {
                // remain on f()
                result = df_dx(xNew, px, py, x0, cx);
            } else {
                // move to g()
                result = 1e18 * 1e18 / df_dx(CurveLib.fInverse(xNew, py, px, y0, x0, cy), py, px, y0, cy);
            }
        } else {
            // swap Y in and X out
            uint256 yNew = reserve1 + amount;
            if (yNew <= y0) {
                // remain on g()
                result = 1e18 * 1e18 / df_dx(yNew, py, px, y0, cy);
            } else {
                // move to f()
                result = df_dx(CurveLib.fInverse(yNew, px, py, x0, y0, cx), px, py, x0, cx);
            }
        }

        return uint256(-result);
    }

    /// @dev EulerSwap derivative helper function to find the price after a swap
    /// Pre-conditions: 0 < x <= x0 <= type(uint112).max, 1 <= {px,py} <= 1e36, c <= 1e18
    function df_dx(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 c) internal pure returns (int256) {
        uint256 r = Math.mulDiv(x0 * x0 / x, 1e18, x, Math.Rounding.Ceil);
        return -int256(px * (c + (1e18 - c) * r / 1e18) / py);
    }
}
