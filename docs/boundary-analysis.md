# Boundary analysis

## Introduction

The EulerSwap automated market maker (AMM) curve is governed by two key functions: `f()` and `fInverse()`. These functions are critical to maintaining protocol invariants and ensuring accurate swap calculations within the AMM. This document provides a detailed boundary analysis of both functions, assessing their Solidity implementations against the equations in the white paper. It ensures that appropriate safety measures are in place to avoid overflow, underflow, and precision loss, and that unchecked operations are thoroughly justified.

## Implementation of `f()`

The `f()` function is part of the EulerSwap core, defined in `CurveLib.sol`, and corresponds to equation (2) in the EulerSwap white paper. The `f()` function is a parameterisable curve that defines the permissible boundary for points in EulerSwap AMMs. The curve allows points on or above and to the right of the curve while restricting others. Its primary purpose is to act as an invariant validator by checking if a hypothetical state `(x, y)` within the AMM is valid. It also calculates swap output amounts for given inputs, though some swap scenarios require `fInverse()`. This section focuses on `f()`, while the analysis for `fInverse()` follows in the next section.

### Derivation

This derivation shows how to implement the `f()` function in Solidity, starting from the theoretical model described in the EulerSwap white paper. The initial equation from the EulerSwap white paper is:

```
y0 + (px / py) * (x0 - x) * (c + (1 - c) * x0 / x)
```

Multiply the second term by `x / x` and scale `c` by `1e18`:

```
y0 + (px / py) * (x0 - x) * ((c * x) + (1e18 - c) * x0) / (x * 1e18)
```

Reorder division by `py` to prepare for Solidity implementation:

```
y0 + px * (x0 - x) * ((c * x) + (1e18 - c) * x0) / (x * 1e18) / py
```

To avoid intermediate overflow, use `Math.mulDiv` in Solidity, which combines multiplication and division safely:

```
y0 + Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18) / py
```

Applying ceiling rounding with `Math.Rounding.Ceil` ensures accuracy:

```
y0 + (Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil) + (py - 1)) / py
```

Adding `(py - 1)` ensures proper ceiling rounding by making sure the result is rounded up when the numerator is not perfectly divisible by `py`.

### Boundary analysis

#### Parameters and pre-conditions

The following parameters and pre-conditions are assumed in this analysis, as documented in the function NatSpec:

```solidity
/// @dev EulerSwap curve
/// @notice Computes the output `y` for a given input `x`.
/// @param x The input reserve value, constrained to 1 <= x <= x0.
/// @param px (1 <= px <= 1e25).
/// @param py (1 <= py <= 1e25).
/// @param x0 (1 <= x0 <= 2^112 - 1).
/// @param y0 (0 <= y0 <= 2^112 - 1).
/// @param c (0 <= c <= 1e18).
/// @return y The output reserve value corresponding to input `x`, guaranteed to satisfy `y0 <= y <= 2^112 - 1`.
```

#### Step-by-step

The arguments to `mulDiv` are safe from overflow:

- **Numerator (arg1):** `px * (x0 - x)` is less than or equal to `1e25 * (2^112 - 1)`, approximately 195 bits
- **Multiplier (arg2):** `c * x + (1e18 - c) * x0` is less than or equal to `1e18 * (2^112 - 1) * 2`, approximately 173 bits
- **Denominator (arg3):** `x * 1e18` is less than or equal to `1e18 * (2^112 - 1)`, approximately 172 bits

If `mulDiv` or the addition with `y0` overflows, the result would exceed `type(uint112).max`. When `mulDiv` overflows, its result would be greater than `2^256 - 1`. Dividing by `py` (maximum `1e25`) yields a result of about `2^173`, which exceeds the `2^112 - 1` limit, meaning these results are invalid as they cannot be satisfied by any swapper.

#### Unchecked math considerations

The arguments to `mulDiv` are protected from overflow as shown above. The `mulDiv` output is further limited to `2^248 - 1` to prevent overflow in subsequent operations:

```solidity
unchecked {
    uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
    require(v <= type(uint248).max, Overflow());
    return y0 + (v + (py - 1)) / py;
}
```

This does not introduce additional failure cases. Even values between `2^248 - 1` and `2^256 - 1` would not reduce to `2^112 - 1`, aligning with the boundary analysis.

## Implementation of `fInverse()`

The `fInverse()` function defined in `CurveLib.sol` represents the positive real root of the solution to a quadratic equation. It is used to find `x` given `y` when quoting for swap input/output amounts in the domain `y >= y0`. Its range is `1 <= x <= x0`. More information about the derivation of the function can be found in the Appendix of the EulerSwap white paper. This documentation covers the implementation in Solidity.

The main components of the particular quadratic equation we wish to solve are:

```
A = cx
B = py / px (y - y0) - (2cx - 1) x0
C = -(1 - cx) x0^2
```

The solution we seek is the positive real root, which is given by:

`x = (-B + sqrt(B^2 - 4AC)) / 2A`

This can be rearranged into a lesser-known form sometimes called the "[citardauq](https://en.wikipedia.org/wiki/Quadratic_formula#Square_root_in_the_denominator)" form as:

`x = 2C / (-B - sqrt(B^2 - 4AC))`

We make use of the more common form when `B <= 0` and the "citardauq" form when `B > 0`, which helps provide greater numerical stability. Since `C` is always negative in our case, note that we can further simplify the equations above by redefining it as a strictly positive quantity `C = (1 - cx) x0^2`, which allows many of the minus signs to cancel. Combined, these simplifications mean we can use:

`x = (B + sqrt(B^2 + 4AC)) / 2A`

when `B < 0`, and

`x = 2C / (B + sqrt(B^2 + 4AC))`

when `B >= 0`.

### Boundary analysis

#### Parameters and pre-conditions

The following parameters and pre-conditions are assumed in this analysis, as documented in the function NatSpec:

```solidity
/// @dev EulerSwap inverse curve
/// @notice Computes the output `x` for a given input `y`.
/// @param y The input reserve value, constrained to y0 <= y <= 2^112 - 1.
/// @param px (1 <= px <= 1e25).
/// @param py (1 <= py <= 1e25).
/// @param x0 (1 <= x0 <= 2^112 - 1).
/// @param y0 (0 <= y0 <= 2^112 - 1).
/// @param c (0 <= c <= 1e18).
/// @return x The output reserve value corresponding to input `y`, guaranteed to satisfy `1 <= x <= x0`.
```

#### Step-by-step

Components `B`, `C`, and `fourAC` are calculated in an unchecked block, so we must ensure that none of their values or intermediate values can overflow or underflow. We use an increased scale of `1e36` for `C` and `fourAC` for increased numerical precision ahead of computing the determinant in the next section of the function.

```solidity
   unchecked {
      int256 term1 = int256(Math.mulDiv(py * 1e18, y - y0, px, Math.Rounding.Ceil)); // scale: 1e36
      int256 term2 = (2 * int256(c) - int256(1e18)) * int256(x0); // scale: 1e36
      B = (term1 - term2) / int256(1e18); // scale: 1e18
      C = Math.mulDiv(1e18 - c, x0 * x0, 1e18, Math.Rounding.Ceil); // scale: 1e36
      fourAC = Math.mulDiv(4 * c, C, 1e18, Math.Rounding.Ceil); // scale: 1e36
   }
```

##### B component

Since `y >= y0` from the function domain and `1 <= py <= 1e25` from the pre-conditions, we know `term1` is always a non-negative integer.

Arguments to `mulDiv`:

- **Numerator (arg1):** `py * 1e18 <= 1e54`
- **Multiplier (arg2):** `y - y0 <= 2^112 - 1`
- **Denominator (arg3):** `1 <= px <= 1e25`

Gives rise to:

- `term1_min = (1 * 1e18 * 1) / 1e25 = 0`
- `term1_max = (1e43 * 5.19e33) / 1 = 5.19e76`

The second term `term2` can be negative or positive:

- `term2_min = (-1e18) * 5.19e33 ≈ -5.19e51`
- `term2_max = (9.999e24) * 5.19e33 ≈ 5.19e58`

Substituting into the expression for `B`, we get:

- `B_min = (1 - 5.19e58) / 1e18 ≈ -5.19e40`
- `B_max = (5.19e76 - (-5.19e51)) / 1e18 ≈ 5.19e58`

All arguments to `mulDiv` and the result itself fit safely within `int256` bounds

##### C component

Arguments to `mulDiv`:

- **Numerator (arg1):** `1e18 - c <= 1e18`
- **Multiplier (arg2):** `x0 * x0 <= (2^112 - 1)^2`
- **Denominator (arg3):** `1e18`

With `0 <= c <= 1e18` from the pre-conditions, we know that `1e18 - c` is a strictly non-negative integer less than `1e18`. The squared term `x0 * x0` reaches its maximum when `x0 = 2^112 - 1`. Thus:

- `C_min = 0`
- `C_max = (1e18 - 1) * (2^112 - 1)^2 / 1e18 ≈ 2.69e67`

All arguments to `mulDiv` and the result itself fit safely within `uint256` bounds.

##### fourAC component

Arguments to `mulDiv`:

- **Numerator (arg1):** `4 * c <= 4e18`
- **Multiplier (arg2):** `C ∈ [0, ~2.69e67]`
- **Denominator (arg3):** `1e18`

Given that `C` is already bounded and `c <= 1e18`, we have:

- `fourAC_min = (4 * c * 0) / 1e18 = 0`
- `fourAC_max = (4e18 * 2.69e67) / 1e18 = 1.076e68`

All arguments to `mulDiv` and the result itself fit safely within `uint256` bounds.

##### Proceeding `absB`, `squaredB`, `discriminant`, and `sqrt` components

`absB` is computed as the absolute value of `B`, so:

- `absB ∈ [0, 5.19e58]`

`squaredB` is computed as:

- If `absB < 1e36`, then `squaredB = absB * absB`, which gives at most `~1e72`.
- If `absB >= 1e36`, then scaled multiplication is used safely to avoid overflow:

```solidity
uint256 scale = computeScale(absB);
squaredB = Math.mulDiv(absB / scale, absB, scale, Math.Rounding.Ceil);
```

In this case, `scale` is the smallest power-of-two scale factor such that the multiplication `absB / scale * absB` does not overflow `uint256`. The resulting value is slightly larger than the true square due to rounding, but remains bounded within `~1e72`.

`discriminant` is then computed differently depending on which path was taken:

- If `absB < 1e36`: `discriminant = squaredB + fourAC`
- If `absB >= 1e36`: `discriminant = squaredB + fourAC / (scale * scale)`

The maximum values in both paths are dominated by the `squaredB` term, which is at most `~1e72`, and the additive `fourAC` or `fourAC / (scale^2)` term remains below `1.08e68`. So in either case:

- `discriminant ∈ [0, ~1e72]`

`sqrt` is the square root of the discriminant:

- `sqrt ∈ [0, 1e36]`, since `sqrt(1e72) = 1e36`

All intermediate results `absB`, `squaredB`, `discriminant`, `sqrt` fit safely within `uint256`.

##### Final calculation of `x`

The final calculation for `x` depends on the sign of `B`:

```solidity
   uint256 x;
   if (B <= 0) {
      // use the regular quadratic formula solution (-b + sqrt(b^2 - 4ac)) / 2a
      x = Math.mulDiv(absB + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 1;
   } else {
      // use the "citardauq" quadratic formula solution 2c / (-b - sqrt(b^2 - 4ac))
      x = Math.ceilDiv(2 * C, absB + sqrt) + 1;
   }
```

When `B <= 0`

Arguments to `mulDiv`:

- **Numerator (arg1):** `absB + sqrt ∈ [0, 5.19e58 + 1e36] ≈ ~5.19e58`
- **Multiplier (arg2):** constant `1e18`
- **Denominator (arg3):** `2 * c ∈ [2, 2e18]`

We have:

```
x_min = Math.mulDiv(1, 1e18, 2e18) + 1 = floor(0.5) + 1 = 1
x_max = (5.19e58 * 1e18) / 2 + 1 = ~2.6e76
```

All arguments to `mulDiv` and the result itself fit safely within `uint256` bounds and `x` satisfies the range requirements of the function.

When `B > 0`:

Arguments to `ceilDiv`:

- **Numerator (arg1):** `2 * C ∈ [0, 2 * 2.69e67] = [0, 5.38e67]`
- **Denominator (arg2):** `absB + sqrt ∈ [1, 5.19e58 + 1e36] ≈ ~5.19e58`

We have:

```
x_min = ceilDiv(0, 5.19e58) + 1 = 0 + 1 = 1
x_max = ceilDiv(5.38e67, 1) + 1 = 5.38e67 + 1
```

All arguments to `ceilDiv` and the result itself fit safely within `uint256` bounds and `x` satisfies the range requirements of the function.

#### Special cases

##### Minimum liquidity concentration `cx = 0`

When the liquidity concentration parameter is `cx = 0`, we have `A = 0`, `C = x0^2` and `B = py * (y - y0) / px + x0`. At first glance, this appears to create problems for `fInverse()`.

Specifically, if `A = 0` and `B <= 0`, we would use the regular quadratic formula solution for `x`, which would invoke

```solidity
x = Math.mulDiv(absB + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 1;
```

In turn, this would revert, because the denominator would be 0.

In practice, however, valid inputs of `y` do not give this result. When `cx = 0`, we know that `B > 0`, meaning that the "citardauq" quadratic branch will be used. Indeed, the curve becomes a constant-product AMM, with:

```
x = x0^2 / (py * (y - y0) / px + x0).
```

##### Maximum liquidity concentration `cx = 1`

When the liquidity concentration parameter is `cx = 1`, we have `A = 1`, `C = (1 - cx) x0^2 = 0` and `B = py * (y - y0) / px - x0`. At first glance, this also appears to create problems for `fInverse()`.

Specifically, if `C = 0` and `B > 0`, we would use the "citardauq" quadratic formula solution for `x`, which would invoke

```solidity
x = Math.ceilDiv(2 * C, absB + sqrt) + 1;
```

In turn, this would incorrectly identify `x = 0`.

In practice, however, valid inputs of `y` do not give this result. When `cx = 1`, we know that the curve becomes a constant-sum AMM, with:

```
x = x0 + py * (y - y0) / px
```

Substituitng into `B`, we obtain

```
B = x - 2 * x0
```

For the "citardauq" quadratic to be invoked we need `B > 0`, which means `x > 2 * x0`, which is not possible, because the domain of the function is `1 <= x <= x0`. We have a contradiction. Thus, we have shown that valid inputs do not invoke this code path.
