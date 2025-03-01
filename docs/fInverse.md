# Boundary analysis of `fInverse()`

## Pre-conditions

- \(y > x_0\)
- \(1e18 \leq p_x, p_y \leq 1e36\) (60 to 120 bits)
- \(1 \leq x_0, y_0 \leq 2^{112} - 1 \approx 5.19e33\) (0 to 112 bits)
- \(1 < c \leq 1e18\) (0 to 60 bits)

## Boundary estimates by code component

### 1. **Component a**

**Expression:**
\[
a = 2c
\]
**Code snippet:**

```solidity
uint256 a = 2 * c;
```

**Boundary analysis:**

- **Upper bound:** \(a = 2 \cdot 1e18 = 2e18 \approx 61 \text{ bits}\)
- **Lower bound:** \(a \approx 2 \approx 2 \text{ bits}\)

### 2. **Component b**

**Expression:**
\[
b = \frac{p_x \cdot (y - x_0) + p_y - 1}{p_y} - \frac{y_0 \cdot (2c - 1e18) + 1e18 - 1}{1e18}
\]
**Code snippet:**

```solidity
int256 b = int256((px * (y - x0) + py - 1) / py) - int256((y0 * (2 * c - 1e18) + 1e18 - 1) / 1e18);
```

**Boundary analysis:**

- **Maximum \(b\)**: \(b = \frac{5.19e69}{1e18} = 5.19e51 \approx 171 \text{ bits}\)
- **Minimum \(b\)**: \(b = -5.19e33 \approx -170 \text{ bits}\)

### 3. **Component b²**

**Expression:**
\[
b^2 = \frac{b^2}{1e18}
\]
**Code snippet:**

```solidity
uint256 bSquared = FullMath.mulDiv(bAbs, bAbs, 1e18) + (bAbs * bAbs % 1e18 == 0 ? 0 : 1);
```

**Boundary analysis:**

- **Maximum \(b^2\)**: \((5.19e51)^2 \approx 2.69e103 \approx 458 \text{ bits}\)
- **FullMath** is used to handle potential **intermediate overflow**, as \(b^2\) can exceed the **uint256** range.

### 4. **Component cPart**

**Expression:**
\[
cPart = \frac{4c \cdot (1e18 - c)}{1e18}
\]
**Code snippet:**

```solidity
uint256 cPart = Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil);
```

**Boundary analysis:**

- **Maximum value:** \(cPart = 4e18 \approx 62 \text{ bits}\)

### 5. **Component y0²**

**Expression:**
\[
y_0^2 = \frac{y_0 \cdot y_0}{1e18}
\]
**Code snippet:**

```solidity
uint256 y0Squared = Math.mulDiv(y0, y0, 1e18, Math.Rounding.Ceil);
```

**Boundary analysis:**

- **Maximum value:** \((5.19e33)^2 = 2.69e67 \approx 224 \text{ bits}\)

### 6. **Component ac4**

**Expression:**
\[
ac4 = \frac{cPart \cdot y_0^2}{1e18}
\]
**Code snippet:**

```solidity
uint256 ac4 = Math.mulDiv(cPart, y0Squared, 1e18, Math.Rounding.Ceil);
```

**Boundary analysis:**

- **Maximum value:** \(ac4 \approx 1.08e68 \approx 226 \text{ bits}\)

### 7. **Component discriminant**

**Expression:**
\[
discriminant = b^2 + ac4
\]
**Code snippet:**

```solidity
uint256 discriminant = bSquared + ac4;
```

**Boundary analysis:**

- **Maximum value:** \(2.69e103 + 1.08e68 \approx 2.69e103 \approx 458 \text{ bits}\)

### 8. **Component square root**

**Expression:**
\[
sqrt = \sqrt{discriminant \cdot 1e18}
\]
**Code snippet:**

```solidity
uint256 sqrt = sqrtRoundUpSafe(discriminant * 1e18);
```

**Boundary analysis:**

- **Maximum value:** \(\sqrt{2.69e103 \cdot 1e18} = 5.19e51 \approx 229 \text{ bits}\)

### 9. **Component final output x**

**Expression:**
\[
x = \frac{\sqrt{discriminant} - b}{2c}
\]
**Code snippet:**

```solidity
return Math.mulDiv(uint256(int256(sqrt) - b), 1e18, a, Math.Rounding.Ceil);
```

**Boundary analysis:**

- **Numerator:** Approx. **229 bits**.
- **Denominator:** At most **61 bits**.
- **Final Output \(x\)**:
  \[
  x \approx \frac{5.19e51}{2e18} \approx 2.6e33 \approx 112 \text{ bits}
  \]
