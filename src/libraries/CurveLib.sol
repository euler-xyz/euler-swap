// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

library CurveLib {
    error Overflow();
    error CurveViolation();

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
    /// @return y The output reserve value corresponding to input `x`, guaranteed to satisfy `y0 <= y <= 2^112 - 1`.
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            require(v <= type(uint248).max, Overflow());
            return y0 + (v + (py - 1)) / py;
        }
    }

    /// @dev EulerSwap inverse curve
    /// @notice Computes the output `x` for a given input `y`.
    /// @param y The input reserve value, constrained to y0 <= y <= 2^112 - 1.
    /// @param px (1 <= px <= 1e25).
    /// @param py (1 <= py <= 1e25).
    /// @param x0 (1 <= x0 <= 2^112 - 1).
    /// @param y0 (0 <= y0 <= 2^112 - 1).
    /// @param c (0 <= c <= 1e18).
    /// @return x The output reserve value corresponding to input `y`, guaranteed to satisfy `1 <= x <= x0`.
    function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        internal
        pure
        returns (uint256)
    {
        // components of quadratic equation
        int256 B;
        uint256 C;
        uint256 fourAC;

        unchecked {
            int256 term1 = int256(Math.mulDiv(py * 1e18, y - y0, px, Math.Rounding.Ceil)); // scale: 1e36
            int256 term2 = (2 * int256(c) - int256(1e18)) * int256(x0); // scale: 1e36
            B = (term1 - term2) / int256(1e18); // scale: 1e18
            C = Math.mulDiv(1e18 - c, x0 * x0, 1e18, Math.Rounding.Ceil); // scale: 1e36
            fourAC = Math.mulDiv(4 * c, C, 1e18, Math.Rounding.Ceil); // scale: 1e36
        }

        uint256 absB = uint256(B >= 0 ? B : -B);
        uint256 squaredB;
        uint256 discriminant;
        uint256 sqrt;
        if (absB < 1e36) {
            // B^2 can be calculated directly at 1e18 scale without overflowing
            unchecked {
                squaredB = absB * absB; // scale: 1e36
                discriminant = squaredB + fourAC; // scale: 1e36
                sqrt = Math.sqrt(discriminant, Math.Rounding.Ceil); // scale: 1e18
            }
        } else {
            // B^2 cannot be calculated directly at 1e18 scale without overflowing
            uint256 scale = computeScale(absB); // calculate the scaling factor such that B^2 can be calculated without overflowing
            squaredB = Math.mulDiv(absB / scale, absB, scale, Math.Rounding.Ceil);
            discriminant = squaredB + fourAC / (scale * scale);
            sqrt = Math.sqrt(discriminant, Math.Rounding.Ceil);
            sqrt = sqrt * scale;
        }

        uint256 x;
        if (B <= 0) {
            // use the regular quadratic formula solution (-b + sqrt(b^2 - 4ac)) / 2a
            x = Math.mulDiv(absB + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 1;
        } else {
            // use the "citardauq" quadratic formula solution 2c / (-b - sqrt(b^2 - 4ac))
            x = Math.ceilDiv(2 * C, absB + sqrt) + 1;
        }

        if (x >= x0) {
            return x0;
        } else {
            return x;
        }
    }

    /// @dev Utility to derive optimal scale for computations in fInverse
    function computeScale(uint256 x) internal pure returns (uint256 scale) {
        // calculate number of bits in x
        uint256 bits = 0;
        while (x > 0) {
            x >>= 1;
            bits++;
        }

        // 2^excessBits is how much we need to scale down to prevent overflow when squaring x
        if (bits > 128) {
            uint256 excessBits = bits - 128;
            scale = 1 << excessBits;
        } else {
            scale = 1;
        }
    }
}
