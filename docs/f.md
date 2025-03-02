# Boundary analysis

There are two main curves defined in EulerSwap. The `f()` curve is the primary EulerSwap curve

`f` (aka the "EulerSwap Function") is a parameterisable curve that defines the boundary of permissible points for EulerSwap AMMs. Points on the curve or above and to-the right are allowed, others are not.

Only formula 3 from the whitepaper is implemented in the EulerSwap core, since this can be used for both domains of the curve by mirroring the parameters. The more complicated formula 4 is a closed-form method for quoting swaps so it can be implemented in a periphery (if desired).

## Implementation of `f`

The code:

```solidity
/// @dev EulerSwap curve definition
    /// Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) public pure returns (uint256) {
        return y0 + (Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil) + (py - 1)) / py;
    }
```

### Derivation

Formula 3 from the whitepaper:

    y0 + (px / py) * (x0 - x) * (c + (1 - c) * (x0 / x))

Multiply second term by `x/x`:

    y0 + (px / py) * (x0 - x) * ((c * x) + (1 - c) * x0) / x

`c` is scaled by `1e18`:

    y0 + (px / py) * (x0 - x) * ((c * x) + (1e18 - c) * x0) / (x * 1e18)

Re-order division by `py`:

    y0 + px * (x0 - x) * ((c * x) + (1e18 - c) * x0) / (x * 1e18) / py

Use `mulDiv` to avoid intermediate overflow:

    y0 + Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18) / py

Round up for both divisions (operation is distributive):

    y0 + (Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil) + (py-1)) / py

# Boundary analysis of `f()`

## Pre-conditions

- \(x \leq x_0\)
- \(1 \leq p_x, p_y \leq 1e36\) (60 to 120 bits)
- \(1 \leq x_0, y_0 \leq 2^{112} - 1 \approx 5.19e33\) (0 to 112 bits)
- \(1 < c \leq 1e18\) (0 to 60 bits)

## Boundary estimates by code component

### 1. **Component A: Multiplication of `px` and `(x0 - x)`**

**Expression:**
\[
A = p_x \cdot (x_0 - x)
\]

**Code snippet:**

```solidity
uint256 A = px * (x0 - x);
```

**Boundary analysis:**

- **Upper bound:**
  \(A = 1e36 \cdot (2^{112} - 1) \approx 2.69e69 \approx 232 \text{ bits}\)
- **Lower bound:**
  \(A \approx 1 \approx 1 \text{ bit}\)

### 2. **Component B: Calculation of `c * x + (1e18 - c) * x0`**

**Expression:**
\[
B = c \cdot x + (1e18 - c) \cdot x_0
\]

**Code snippet:**

```solidity
uint256 B = c * x + (1e18 - c) * x0;
```

**Boundary analysis:**

- **Upper bound:**
  \(B = 1e18 \cdot (2^{112} - 1) \cdot 2 \approx 1.08e52 \approx 173 \text{ bits}\)
- **Lower bound:**
  \(B \approx 1 \approx 1 \text{ bit}\)

### 3. **Component C: Division of `B` by `x * 1e18`**

**Expression:**
\[
C = \frac{B}{x \cdot 1e18}
\]

**Code snippet:**

```solidity
uint256 C = Math.mulDiv(A, B, x * 1e18, Math.Rounding.Ceil);
```

**Boundary analysis:**

- **Numerator upper bound:**
  \(A \cdot B = 2.69e69 \cdot 1.08e52 \approx 2.9e121 \approx 405 \text{ bits}\)

- **Denominator upper bound:**
  \(x \cdot 1e18 = (2^{112} - 1) \cdot 1e18 \approx 1.08e52 \approx 172 \text{ bits}\)

- **Maximum value of `C`:**
  \(C = \frac{2.9e121}{1.08e52} \approx 2.69e69 \approx 233 \text{ bits}\)

### 4. **Final Output `y`**

**Expression:**
\[
y = y_0 + \frac{C + (p_y - 1)}{p_y}
\]

**Code snippet:**

```solidity
uint256 y = y0 + (C + (py - 1)) / py;
```

**Boundary analysis:**

- **Numerator upper bound:**
  \(C + (p_y - 1) \approx 2.69e69 + 1e36 \approx 2.69e69 \approx 233 \text{ bits}\)

- **Denominator `p_y` maximum:**
  \(1e36 \approx 120 \text{ bits}\)

- **Final Output `y`:**
  \[
  y = y_0 + \frac{2.69e69}{1e36} \approx 5.19e33 + 2.69e33 \approx 7.88e33 \approx 113 \text{ bits}\)

## Notes

The `f()` function's maximum possible output is bounded to approximately **113 bits**, which is within the `uint112` limit of **112 bits**. Therefore, while the intermediate steps of the function involve large bit-widths, the final output remains safe and well within the limits imposed by the smart contract. Overflow risks are mitigated by the bounds on the `mulDiv` and the pre-conditions set by the function's inputs.

If amounts/prices are large, and we travel too far down the curve, then `mulDiv` (or the subsequent `y0` addition) could overflow because its output value cannot be represented as a `uint256`. However, these output values would never be valid anyway, because they exceed `type(uint112).max`.

To see this, consider the case where `mulDiv` fails due to overflow. This means that its result would've been greater than `2**256 - 1`. Dividing this value by the largest allowed value for `py` (`1e36`) gives approximately `2**136`, which is greater than the maximum allowed amount value of `2**112 - 1`. Both the rounding up operation and the final addition of `y0` can only further _increase_ this value. This means that all cases where `mulDiv` or the subsequent additions overflow would involve `f()` returning values that are impossible for a swapper to satisfy, so they would revert anyways.
