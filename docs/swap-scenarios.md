# Swapping scenarios

The swap function operates within two potential domains for `x`:

- **Domain 1:** `0 < x < x0`
- **Domain 2:** `x > x0`

We allow swaps in or out of both the `X` and `Y` assets. Depending on the swap, the system may either remain in the current domain or transition to the other domain. All scenarios assume we start in Domain 1.

## Function definitions

- `y = f(x)`: Function that maps `x` to `y` in Domain 1.
- `x = fInverse(y)`: Inverse function that maps `y` to `x` in Domain 1.
- `x = g(y)`: Function that maps `y` to `x` in Domain 2.

## 1a. Swap `xIn` and remain in domain 1

**Calculation steps:**

1. `xNew = x + xIn`

2. `yNew = f(xNew)`

**Invariant check:**

`yNew >= f(x)`

## 1b. Swap `xIn` and move to domain 2

**Calculation steps:**

1. `xNew = x + xIn`

2. `yNew = fInverse(x)`

**Invariant check:**

`xNew >= g(yNew)`

## 2. Swap `yIn` and remain in domain 1

**Calculation steps:**

1. `yNew = y + yIn`

2. `xNew = fInverse(yNew)`

**Invariant check:**

`yNew >= f(xNew)`

## 3. Swap `xOut` and remain in domain 1

**Calculation steps:**

1. `xNew = x - xOut`

2. `yNew = f(xNew)`

**Invariant check:**

`yNew >= f(xNew)`

## 4a. Swap `yOut` and remain in domain 1

**Calculation steps:**

1. `yNew = y - yOut`

2. `xNew = f(xNew)`

**Invariant check:**

`yNew >= f(xNew)`

## 4b. Swap `yOut` and move to domain 2

**Calculation steps:**

1. `yNew = y - yOut`

2. `xNew = g(yNew)`

**Invariant check:**

`xNew >= g(yNew)`
