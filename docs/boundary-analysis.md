# Boundary analysis

## Introduction

The EulerSwap automated market maker (AMM) curve is governed by two key functions: `f()` and `fInverse()`. These functions are critical to maintaining protocol invariants and ensuring accurate swap calculations within the AMM. This document provides a detailed boundary analysis of both functions, assessing their Solidity implementations against the equations in the white paper. It ensures that appropriate safety measures are in place to avoid overflow, underflow, and precision loss, and that unchecked operations are thoroughly justified. We assume throughout the following pre-conditions.

## Pre-conditions

### Domain and range

The curve functions are specified in `f()` and `fInverse()` inside `CurveLib.sol`.

The function `f()` operates on the domain `1 <= x <= x0`, where the output satisfies `y >= y0`.  
The function `fInverse()` operates on the domain `y >= y0`, where the output satisfies `1 <= x <= x0`.

### Parameter ranges

Valid parameter ranges for both functions are:

```
0 < px, py <= 1e36
0 < c <= 1e18
0 <= x0, y0 <= type(uint112).max
```

These are enforced in the `activate()` function of `EulerSwap.sol`.

Additional constraints are placed on `px` and `py` to prevent overflow in `fInverse()` under extreme parameterisations of the price factor parameters. These conditions are:

```
py * 1e18 * (y - y0) <= type(uint256).max
px * 1e18 * (x - x0) <= type(uint256).max
```

Assuming the worst-case values for `y` and `x`, we obtain:

```
py <= type(uint256).max / (1e18 * (type(uint112).max - y0))
px <= type(uint256).max / (1e18 * (type(uint112).max - x0))
```

## Implementation of function `f()`

The `f()` function is part of the EulerSwap core, defined in `EulerSwap.sol`, and corresponds to equation (2) in the EulerSwap white paper. The `f()` function is a parameterisable curve in the `EulerSwap` contract that defines the permissible boundary for points in EulerSwap AMMs. The curve allows points on or above and to the right of the curve while restricting others. Its primary purpose is to act as an invariant validator by checking if a hypothetical state `(x, y)` within the AMM is valid. It also calculates swap output amounts for given inputs, though some swap scenarios require `fInverse()`.

### Derivation

This derivation shows how to implement the `f()` function in Solidity, starting from the theoretical model described in the EulerSwap white paper. The initial equation from the EulerSwap white paper is:

\[
y_0 + \left(\frac{p_x}{p_y}\right) (x_0 - x) \left(c + (1 - c) \frac{x_0}{x}\right)
\]

Multiply the second term by \(\frac{x}{x}\) and scale `c` by \(1e18\):

\[
y_0 + \left(\frac{p_x}{p_y}\right) (x_0 - x) \frac{(c \cdot x) + (1e18 - c) \cdot x_0}{x \cdot 1e18}
\]

Reorder division by \(p_y\) to prepare for Solidity implementation:

\[
y_0 + p_x \cdot (x_0 - x) \cdot \frac{(c \cdot x) + (1e18 - c) \cdot x_0}{x \cdot 1e18} \cdot \frac{1}{p_y}
\]

To avoid intermediate overflow, use `Math.mulDiv` in Solidity, which combines multiplication and division safely:

\[
y_0 + \frac{\text{Math.mulDiv}(p_x \cdot (x_0 - x), c \cdot x + (1e18 - c) \cdot x_0, x \cdot 1e18)}{p_y}
\]

Applying ceiling rounding with `Math.Rounding.Ceil` ensures accuracy:

\[
y_0 + \left(\text{Math.mulDiv}(p_x \cdot (x_0 - x), c \cdot x + (1e18 - c) \cdot x_0, x \cdot 1e18, \text{Math.Rounding.Ceil}) + (p_y - 1)\right) / p_y
\]

Adding `(p_y - 1)` ensures proper ceiling rounding by making sure the result is rounded up when the numerator is not perfectly divisible by `p_y`.

### Boundary analysis

#### Step-by-step

The arguments to `mulDiv` are safe from overflow:

- **Arg 1:** `px * (x0 - x)` ≤ `1e36 * (2**112 - 1)` ≈ 232 bits
- **Arg 2:** `c * x + (1e18 - c) * x0` ≤ `1e18 * (2**112 - 1) * 2` ≈ 173 bits
- **Arg 3:** `x * 1e18` ≤ `1e18 * (2**112 - 1)` ≈ 172 bits

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

## Implementation of function `fInverse()`

The `fInverse()` function, defined in `EulerSwapPeriphery.sol`, is part of the periphery because it is not required as an invariant. Instead, its sole purpose is to facilitate specific swap input and output calculations that cannot be managed by `f()`. This function maps to equation (22) in the Appendix of the EulerSwap white paper.

### Boundary analysis

#### Pre-conditions

- \(y > y_0\)
- \(1e18 \leq p_x, p_y \leq 1e36\) (60 to 120 bits)
- \(1 \leq x_0, y_0 \leq 2^{112} - 1 \approx 5.19e33\) (0 to 112 bits)
- \(1 < c \leq 1e18\) (0 to 60 bits)

#### Step-by-step

1. **A component (`A = 2 * c`)**

   - Since `c <= 1e18`, `A = 2 * c <= 2e18`, well within `uint256` capacity (max `2**256 - 1`).

2. **B component calculation**

   - `B = int256((px * (y - y0) + py - 1) / py) - int256((x0 * (2 * c - 1e18) + 1e18 - 1) / 1e18)`
   - The first term is bounded by `(px * (y - y0)) / py`, where `px, py <= 1e36` and `(y - y0) <= 2**112 - 1`.
   - The second term scales `x0` with `(2 * c - 1e18)`, keeping the result well within the `int256` bounds due to controlled arithmetic and the limits on `c` and `x0`.

3. **Absolute value and B² computation**

   - `absB = B < 0 ? uint256(-B) : uint256(B)`
   - `squaredB = Math.mulDiv(absB, absB, 1e18, Math.Rounding.Ceil)`
   - As `absB` is derived from `B`, and `B` is bounded, `squaredB` remains within a safe range.

4. **4AC Component (`AC4 = AC4a * AC4b / 1e18`)**

   - `AC4a = Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil)`
   - `4 * c * (1e18 - c)` has a maximum of `1e18 * 1e18 = 1e36`, divided by `1e18`, the result ≤ `1e18`.
   - `AC4b = Math.mulDiv(x0, x0, 1e18, Math.Rounding.Ceil)`
   - The maximum value of `x0 * x0` is `(2**112 - 1)² ≈ 2**224`, safely within the `uint256` range.

5. **Discriminant calculation**

   - `discriminant = (squaredB + AC4) * 1e18`
   - Since both `squaredB` and `AC4` are bounded by `uint256`, multiplying by `1e18` does not cause overflow.

6. **Square root computation and adjustment**

   - `uint256 sqrt = Math.sqrt(discriminant)`
   - The square root of a `uint256` value is always within `uint128`, making this operation safe.
   - Adjustment step `sqrt = (sqrt * sqrt < discriminant) ? sqrt + 1 : sqrt` maintains precision without overflow.

7. **Final computation of `x`**
   - `Math.mulDiv(uint256(int256(sqrt) - B), 1e18, A, Math.Rounding.Ceil)`
   - The subtraction and multiplication are controlled by previous bounds, ensuring no overflow.
   - Division by `A` is safe as `A` is non-zero and small (`≤ 2e18`).

#### Unchecked math considerations

As above, the use of unchecked arithmetic is safe because all inputs are bounded by pre-conditions.

## Conclusion

The `f()` and `fInverse()` functions of EulerSwap are implemented with rigorous safety measures, using `Math.mulDiv` for safe arithmetic and applying ceiling rounding to maintain precision. Boundary analysis shows that all potential overflow scenarios are precluded by pre-condition checks and bounded operations, justifying the use of unchecked math in the Solidity implementation.
