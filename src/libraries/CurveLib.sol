// SPDX-License-Identifier: BUSL-1.1

// Copyright (c) 2024-2025 Euler Labs Ltd
// Copyright (c) 2024-2025 ZeroEx Inc

// The routines in this file were optimised and improved by Duncan Townsend
// and Lazaro Raul Iglesias Vera from ZeroEx Inc. Their work is MIT licensed
// and is used here with their permission.

pragma solidity ^0.8.27;

import {UnsafeMath, Math} from "../math/UnsafeMath.sol";
import {FullMath} from "../math/FullMath.sol";
import {FastLogic} from "../math/FastLogic.sol";
import {Clz} from "../math/Clz.sol";
import {Sqrt} from "../math/Sqrt.sol";

import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

library CurveLib {
    using UnsafeMath for uint256;
    using UnsafeMath for int256;
    using Math for uint256;
    using FullMath for uint256;
    using Clz for uint256;
    using Sqrt for uint256;
    using FastLogic for bool;

    /// @notice Returns true if the specified reserve amounts would be acceptable, false otherwise.
    /// Acceptable points are on, or above and to-the-right of the swapping curve.
    function verify(IEulerSwap.DynamicParams memory p, uint256 newReserve0, uint256 newReserve1)
        internal
        pure
        returns (bool)
    {
        if (newReserve0 > type(uint112).max || newReserve1 > type(uint112).max) return false;
        if (newReserve0 < p.minReserve0 || newReserve1 < p.minReserve1) return false;

        if (newReserve0 >= p.equilibriumReserve0) {
            if (newReserve1 >= p.equilibriumReserve1) return true;
            return newReserve0
                >= f(newReserve1, p.priceY, p.priceX, p.equilibriumReserve1, p.equilibriumReserve0, p.concentrationY);
        } else {
            if (newReserve1 < p.equilibriumReserve1) return false;
            return newReserve1
                >= f(newReserve0, p.priceX, p.priceY, p.equilibriumReserve0, p.equilibriumReserve1, p.concentrationX);
        }
    }

    /// @dev EulerSwap curve
    /// @notice Computes the output `y` for a given input `x`.
    /// @param x The input reserve value, constrained to 1 <= x <= x0.
    /// @param px (1 <= px <= 1e25).
    /// @param py (1 <= py <= 1e25).
    /// @param x0 (1 <= x0 <= 2^112 - 1).
    /// @param y0 (0 <= y0 <= 2^112 - 1).
    /// @param c (0 <= c <= 1e18).
    /// @return y The output reserve value corresponding to input `x`, guaranteed to satisfy `y0 <= y <= 2^112 - 1`, or `type(uint256).max` on overflow.
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        uint256 output;

        unchecked {
            if (c == 1e18) {
                // `c == 1e18` indicates that this is a constant-sum curve. Convert `x` into `y`
                // using `px` and `py`
                uint256 v = ((x0 - x) * px).unsafeDivUp(py); // scale: 1; units: token Y
                output = y0 + v;
            } else {
                uint256 a = px * (x0 - x); // scale: 1e18; units: none; range: 196 bits
                uint256 b = c * x + (1e18 - c) * x0; // scale: 1e18; units: token X; range: 172 bits
                uint256 d = 1e18 * x * py; // scale: 1e36; units: token X / token Y; range: 255 bits
                uint256 v = a.saturatingMulDivUp(b, d); // scale: 1; units: token Y
                output = y0.saturatingAdd(v);
            }

            if (output > type(uint112).max) return type(uint256).max;
        }

        return output;
    }

    /// @dev EulerSwap inverse curve
    /// @dev Implements equations 23 through 27 from the whitepaper.
    /// @notice Computes the output `x` for a given input `y`.
    /// @notice The combination `x0 == 0 && cx < 1e18` is invalid.
    /// @param y The input reserve value, constrained to `y0 <= y <= 2^112 - 1`. (An amount of tokens in base units.)
    /// @param px (1 <= px <= 1e25). A fixnum with a basis of 1e18.
    /// @param py (1 <= py <= 1e25). A fixnum with a basis of 1e18.
    /// @param x0 (0 <= x0 <= 2^112 - 1). An amount of tokens in base units.
    /// @param y0 (0 <= y0 <= 2^112 - 1). An amount of tokens in base units.
    /// @param cx (0 <= cx <= 1e18). A fixnum with a basis of 1e18.
    /// @return x The output reserve value corresponding to input `y`, guaranteed to satisfy `0 <= x <= x0`. (An amount of tokens in base units.)
    /// @dev The maximum possible error (overestimate only) in `x` from the smallest such value that will still pass `verify` is 1 wei.
    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 cx)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            // The value `B` is implicitly computed as:
            //     [(y - y0) * py * 1e18 - (cx * 2 - 1e18) * x0 * px] / px
            // We only care about the absolute value of `B` for use later, so we separately extract
            // the sign of `B` and its absolute value
            bool sign; // `true` when `B` is negative
            uint256 absB; // scale: 1e18; units: token X; range: 255 bits
            {
                uint256 term1 = 1e18 * ((y - y0) * py + x0 * px); // scale: 1e36; units: none; range: 256 bits
                uint256 term2 = (cx << 1) * x0 * px; // scale: 1e36; units: none; range: 256 bits

                // Ensure that the result will be positive
                uint256 difference; // scale: 1e36; units: none; range: 256 bits
                (difference, sign) = term1.absDiff(term2);

                // If `sign` is true, then we want to round up. Compute the carry bit
                bool carry = (0 < difference.unsafeMod(px)).and(sign);
                absB = difference.unsafeDiv(px).unsafeInc(carry);
            }

            // `twoShift` is how much we need to shift right (the log of the scaling factor) to
            // prevent overflow when computing `squaredB`, `fourAC`, or `discriminant`. `shift` is
            // half that; the amount we have to shift left by after taking the square root of
            // `discriminant` to get back to a basis of 1e18
            uint256 shift;
            {
                uint256 shiftSquaredB = absB.bitLength().saturatingSub(127);
                // 3814697265625 is 5e17 with all the trailing zero bits removed to make the
                // constant smaller. The argument of `saturatingSub` is reduced to compensate
                uint256 shiftFourAc = (x0 * 3814697265625).bitLength().saturatingSub(109);
                shift = shiftSquaredB < shiftFourAc ? shiftFourAc : shiftSquaredB;
            }
            uint256 twoShift = shift << 1;

            uint256 x; // scale: 1; units: token X; range: 113 bits
            if (sign) {
                // `B` is negative; use the regular quadratic formula; everything rounds up.
                //     (-b + sqrt(b^2 - 4ac)) / 2a
                // Because `B` is negative, `absB == -B`; we can avoid negation.

                // `fourAC` is actually the value $-4ac$ from the "normal" conversion of the
                // constant function to its quadratic form. Computing it like this means we can
                // avoid subtraction (and potential underflow)
                uint256 fourAC = (cx * (1e18 - cx) << 2).unsafeMulShiftUp(x0 * x0, twoShift); // scale: 1e36 >> twoShift; units: (token X)^2; range: 254 bits

                uint256 squaredB = absB.unsafeMulShiftUp(absB, twoShift); // scale: 1e36 >> twoShift; units: (token X)^2; range: 254 bits
                uint256 discriminant = squaredB + fourAC; // scale: 1e36 >> twoShift; units: (token X)^2; range: 254 bits
                uint256 sqrt = discriminant.sqrtUp() << shift; // scale: 1e18; units: token X; range: 172 bits

                x = (absB + sqrt).unsafeDivUp(cx << 1);
            } else {
                // `B` is nonnegative; use the "citardauq" quadratic formula; everything except the
                // final division rounds down.
                //     2c / (-b - sqrt(b^2 - 4ac))

                // `fourAC` is actually the value $-4ac$ from the "normal" conversion of the
                // constant function to its quadratic form. Therefore, we can avoid negation of
                // `absB` and both subtractions
                uint256 fourAC = (cx * (1e18 - cx) << 2).unsafeMulShift(x0 * x0, twoShift); // scale: 1e36 >> twoShift; units: (token X)^2; range: 254 bits

                uint256 squaredB = absB.unsafeMulShift(absB, twoShift); // scale: 1e36 >> twoShift; units: (token X)^2; range: 254 bits
                uint256 discriminant = squaredB + fourAC; // scale: 1e36 >> twoShift; units: (token X)^2; range: 255 bits
                uint256 sqrt = discriminant.sqrt() << shift; // scale: 1e18; units: token X; range: 255 bits

                // If `cx == 1e18` and `B == 0`, we evaluate `0 / 0`, which is `0` on the EVM. This
                // just so happens to be the correct answer
                x = ((1e18 - cx) << 1).unsafeMulDivUpAlt(x0 * x0, absB + sqrt);
            }

            // Handle any rounding error that could produce a value out of the bounds established by
            // the NatSpec
            return x.unsafeDec(x > x0);
        }
    }
}
