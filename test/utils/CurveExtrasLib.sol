// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

library CurveExtrasLib {
    /// @dev EulerSwap derivative helper function to find the price after a swap
    /// Pre-conditions: 0 < x <= x0 <= type(uint112).max, 1 <= {px,py} <= 1e36, c <= 1e18
    function df_dx(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 c) internal pure returns (int256) {
        uint256 r = Math.mulDiv(x0 * x0 / x, 1e18, x, Math.Rounding.Ceil);
        return -int256(px * (c + (1e18 - c) * r / 1e18) / py);
    }
}
