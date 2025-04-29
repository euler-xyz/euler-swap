# Boundary analysis

## Introduction

The EulerSwap automated market maker (AMM) curve is governed by two key functions: f() and fInverse(). These functions are critical to maintaining protocol invariants and ensuring accurate swap calculations within the AMM. This document provides a detailed boundary analysis of both functions, assessing their Solidity implementations against the equations in the white paper. It ensures that appropriate safety measures are in place to avoid overflow, underflow, and precision loss, and that unchecked operations are thoroughly justified.

## Implementation of function `f()`

The `f()` function is part of the EulerSwap core, defined in `EulerSwap.sol`, and corresponds to equation (2) in the EulerSwap white paper. The `f()` function is a parameterisable curve in the `EulerSwap` contract that defines the permissible boundary for points in EulerSwap AMMs. The curve allows points on or above and to the right of the curve while restricting others. Its primary purpose is to act as an invariant validator by checking if a hypothetical state `(x, y)` within the AMM is valid. It also calculates swap output amounts for given inputs, though some swap scenarios require `fInverse()`.

### Derivation

This derivation shows how to implement the `f()` function in Solidity, starting from the theoretical model described in the EulerSwap white paper. The initial equation from the EulerSwap white paper is:

```
y0 + (px / py) * (x0 - x) * (c + (1 - c) * (x0 / x))
```

Multiply the second term by `x / x` and scale `c` by `1e18`:

```
y0 + (px / py) * (x0 - x) * ((c * x + (1e18 - c) * x0) / (x * 1e18))
```

Reorder division by `py` to prepare for Solidity implementation:

```
y0 + px * (x0 - x) * ((c * x + (1e18 - c) * x0) / (x * 1e18)) * (1 / py)
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

#### Pre-conditions

- `x <= x0`
- `1e18 <= px, py <= 1e36` (60 to 120 bits)
- `1 <= x0, y0 <= 2^112 - 1 ≈ 5.19e33` (0 to 112 bits)
- `1 < c <= 1e18` (0 to 60 bits)

#### Step-by-step

The arguments to `mulDiv` are safe from overflow:

- **Arg 1:** `px * (x0 - x) <= 1e36 * (2**112 - 1)` ≈ 232 bits
- **Arg 2:** `c * x + (1e18 - c) * x0 <= 1e18 * (2**112 - 1) * 2` ≈ 173 bits
- **Arg 3:** `x * 1e18 <= 1e18 * (2**112 - 1)` ≈ 172 bits

If `mulDiv` or the addition with `y0` overflows, the result would exceed `type(uint112).max`. When `mulDiv` overflows, its result would be > `2**256 - 1`. Dividing by `py` (`1e36` max) gives ~`2**136`, which exceeds the `2**112 - 1` limit, meaning these results are invalid as they cannot be satisfied by any swapper.

#### Unchecked math considerations

The arguments to `mulDiv` are protected from overflow as demonstrated above. The `mulDiv` output is further limited to `2**248 - 1` to prevent overflow in subsequent operations:

```solidity
unchecked {
    uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
    require(v <= type(uint248).max, Overflow());
    return y0 + (v + (py - 1)) / py;
}
```

This does not introduce additional failure cases. Even values between `2**248 - 1` and `2**256 - 1` would not reduce to `2**112 - 1`, aligning with the boundary analysis.

### Implementation of function `fInverse()`

The `fInverse()` function defined in `CurveLib.sol` represents the positive real root of the solution to a quadratic equation. It is used to find `x` given `y` when quoting for swap input/output amounts in the domain `0 <= x <= x0`. More information about the derivation of the function can be found in the Appendix of the EulerSwap white paper. This documentation covers the implementation in Solidity.

The main components of the particular quadratic equation we wish to solve are:

`A = cx`
`B = py / px (y - y0) - (2cx - 1) x0`
`C = -(1 - cx) x0^2`

The solution we seek is the positive real root, which is given by:

`x = (-B + sqrt(B^2 - 4AC)) / 2A`

This can be rearranged into a lesser-known form sometimes called the "[citardauq](https://en.wikipedia.org/wiki/Quadratic_formula#Square_root_in_the_denominator)" form as:

`x = 2C / (-B - sqrt(B^2 - 4AC))`

We make use of the more common form when `B <= 0` and the "citardauq" form when `B > 0`, which helps provide greater numerical stability. Since `C` is always negative in our case, note that we can further simplify the equations above by redefining it as a strictly positive quantity `C = (1 - cx) x0^2`, which allows many of the minus signs to cancel. Combined, these simplifications mean we can use:

`x = (B + sqrt(B^2 + 4AC)) / 2A`

when `B < 0`, and

`x = 2C / (B + sqrt(B^2 + 4AC))`

when `B >= 0`.

The components we consider in the boundary analysis below are therefore:

`B = py / px (y - y0) - (2cx - 1) x0`
`C = (1 - cx) x0^2`
`fourAC = cx (1 - cx) x0^2`

### Boundary analysis

#### Pre-conditions

- `y > y0`
- `1e18 <= px, py <= 1e36`
- `1 <= x0, y0 <= 2^112 - 1`
- `1 < c <= 1e18`

#### Step-by-step

Components `B`, `C`, and `fourAC` are calculated in an unchecked block, so we must ensure that none of their intermediate values cause overflow or underflow.

##### B component

```solidity
int256 term1 = int256(Math.mulDiv(py * 1e18, y - y0, px, Math.Rounding.Ceil)); // scale: 1e36
int256 term2 = (2 * int256(c) - int256(1e18)) * int256(x0); // scale: 1e36
B = (term1 - term2) / int256(1e18); // scale: 1e18
```

Since `y > y0`, `term1` is always a positive integer. Arguments to `mulDiv`:

- **Arg 1:** `py * 1e18 <= 1e54`
- **Arg 2:** `y - y0 <= 2^112 - 1`
- **Arg 3:** `1e18 <= px <= 1e36`

Gives rise to:

- `term1_min = (1e18 * 1e18 * 1) / 1e36 = 1`
- `term1_max = (1e36 * 1e18 * (2^112 - 1)) / 1e18 ≈ 5.19e69`

The second term `term2` can be negative or positive:

- `term2_min = (-1e18 + 2) * (2^112 - 1) ≈ -5.19e51`
- `term2_max = 1e18 * (2^112 - 1) ≈ 5.19e51`

Substituting into the expression for `B`, we get:

- `B_min = (1 - 1e18 * (2^112 - 1)) / 1e18 ≈ -5.19e33`
- `B_max = ((1e36 * (2^112 - 1)) - (-1e18 * (2^112 - 1))) / 1e18 ≈ 5.19e51`

So, `B ∈ [-5.19e33, 5.19e51]`, within `int256` bounds.

##### C component

```solidity
uint256 C = Math.mulDiv((1e18 - c), x0 * x0, 1e18, Math.Rounding.Ceil); // scale: 1e36
```

Arguments to `mulDiv`:

- **Arg 1:** `1e18 - c < 1e18`
- **Arg 2:** `x0 * x0 <= (2^112 - 1)^2`
- **Arg 3:** `1e18`

With `1 < c <= 1e18`, we know that `1e18 - c` is a strictly positive integer less than `1e18`. The squared term `x0 * x0` reaches its maximum when `x0 = 2^112 - 1`. Thus:

- `C_min = 1`
- `C_max = (1e18 - 1) * (2^112 - 1)^2 / 1e18 ≈ 2.69e49`

So, `C ∈ [1, 2.69e49]`, within `uint256` bounds.

##### fourAC component

```solidity
uint256 fourAC = Math.mulDiv(4 * c, C, 1e18, Math.Rounding.Ceil); // scale: 1e36
```

Arguments to `mulDiv`:

- **Arg 1:** `4 * c <= 4e18`
- **Arg 2:** `C ∈ [1, 2.69e49]`
- **Arg 3:** `1e18`

Given that `C` is already bounded and `c <= 1e18`, we have:

- `fourAC_min = (4 * 1 * 1) / 1e18 = 1` (rounded up)
- `fourAC_max = (4e18 * 2.69e49) / 1e18 = 1.076e50`

Thus, `fourAC ∈ [1, 1.08e50]`, within `uint256` bounds.

##### Proceeding absB, squaredB, discriminant, and sqrt components

`absB` is computed as the absolute value of `B`, so:

- `absB ∈ [0, 5.19e51]`

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

The maximum values in both paths are dominated by the `squaredB` term, which is at most `~1e72`, and the additive `fourAC` or `fourAC / (scale^2)` term remains below `1.08e50`. So in either case:

- `discriminant ∈ [0, ~1e72]`

`sqrt` is the square root of the discriminant:

- `sqrt ∈ [0, 1e36]`, since `sqrt(1e72) = 1e36`

All intermediate results (`absB`, `squaredB`, `discriminant`, `sqrt`) fit safely within `uint256`.

##### Final calculation of x

The final calculation for `x` depends on the sign of `B`:

```solidity
if (B <= 0) {
    x = Math.mulDiv(absB + sqrt, 1e18, 2 * c, Math.Rounding.Ceil) + 1;
} else {
    x = (2 * C + (absB + sqrt - 1)) / (absB + sqrt) + 1;
}
```

###### When `B <= 0`:

- `absB + sqrt ∈ [0, ~2 * 5.19e51] = ~1.04e52`
- The denominator `2 * c ∈ [2, 2e18]`
- `Math.mulDiv(absB + sqrt, 1e18, 2 * c)` scales back to a fixed-point value.

So:

- `x_min ≈ (1 * 1e18) / (2e18) + 1 = 1`
- `x_max ≈ (1.04e52 * 1e18) / 2 = 5.2e69 + 1`

This fits safely within `uint256`.

###### When `B > 0`:

- `numerator = 2 * C + (absB + sqrt - 1) ∈ [2 + 0, 2 * 2.69e49 + 1.04e52] ≈ 1.09e52`
- `denominator = absB + sqrt ∈ [1, ~1.04e52]`
- The maximum result occurs when numerator ≈ denominator → `x ≈ 2`
- The minimum value occurs when numerator is small and denominator is large → `x ≈ 1`

In both cases, the result is clamped to at most `x0`, which is at most `2^112 - 1 ≈ 5.19e33`

So:

- `x ∈ [1, min(5.2e69, x0)]`

Final clamping ensures that:

```solidity
if (x >= x0) {
    return x0;
} else {
    return x;
}
```

Therefore, final result `x` always returns a value in `[1, x0]`, safely within bounds.
