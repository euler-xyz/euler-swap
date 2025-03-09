# Swapping scenarios

The swap function operates within two potential domains for `x`:

- **Domain 1:** `0 < x < x0`
- **Domain 2:** `x > x0`

We allow swaps in or out of both the `X` and `Y` assets. Depending on the swap, the system may either remain in the current domain or transition to the other domain.

## Function definitions

- `y = f(x)`: Function that maps `x` to `y` in domain 1.
- `x = fInverse(y)`: Inverse function that maps `y` to `x` in domain 1.
- `x = g(y)`: Function that maps `y` to `x` in domain 2.

## Invariant checks

We always check the invariant using the cheapest function to compute. This means we check:

- `f(x)` if in domain 1.
- `g(y)` if in domain 2.

## Starting in domain 1

### 1a. Swap `xIn` and remain in domain 1

**Calculation steps:**

1. `xNew = x + xIn`

2. `yNew = f(xNew)`

**Invariant check:**

`yNew >= f(xNew) = f(x + xIn)`

### 1b. Swap `xIn` and move to domain 2

**Calculation steps:**

1. `xNew = x + xIn`

2. `yNew = fInverse(xNew)`

**Invariant check:**

`xNew >= g(yNew) = g(fInverse(xNew)) = g(fInverse(x + xIn))`

### 2. Swap `yIn` and remain in domain 1

**Calculation steps:**

1. `yNew = y + yIn`

2. `xNew = fInverse(yNew)`

**Invariant check:**

`yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y + yIn))`

### 3. Swap `xOut` and remain in domain 1

**Calculation steps:**

1. `xNew = x - xOut`

2. `yNew = f(xNew)`

**Invariant check:**

`yNew >= f(xNew) = f(x - xOut)`

### 4a. Swap `yOut` and remain in domain 1

**Calculation steps:**

1. `yNew = y - yOut`

2. `xNew = fInverse(yNew)`

**Invariant check:**

`yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y - yOut))`

### 4b. Swap `yOut` and move to domain 2

**Calculation steps:**

1. `yNew = y - yOut`

2. `xNew = g(yNew)`

**Invariant check:**

`xNew >= g(yNew) = g(y - yOut)`

## Starting in domain 2

### 5. Swap `xIn` and remain in domain 2

**Calculation steps:**

1. `xNew = x + xIn`

2. `yNew = fInverse(xNew)`

**Invariant check:**

`xNew >= g(yNew) = g(fInverse(xNew)) = g(fInverse(x + xIn))`

### 6a. Swap `yIn` and remain in domain 2

**Calculation steps:**

1. `yNew = y + yIn`

2. `xNew = g(yNew)`

**Invariant check:**

`xNew >= g(yNew) = g(y + yIn)`

### 6b. Swap `yIn` and move to domain 1

**Calculation steps:**

1. `yNew = y + yIn`

2. `xNew = fInverse(yNew)`

**Invariant check:**

`yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y + yIn))`

### 7a. Swap `xOut` and remain in domain 2

**Calculation steps:**

1. `xNew = x - xOut`

2. `yNew = fInverse(xNew)`

**Invariant check:**

`xNew >= g(xNew) = g(x - xOut)`

### 7b. Swap `xOut` and move to domain 1

**Calculation steps:**

1. `xNew = x - xOut`

2. `yNew = f(xNew)`

**Invariant check:**

`yNew >= f(xNew) = f(x - xOut)`

### 8. Swap `yOut` and remain in domain 2

**Calculation steps:**

1. `yNew = y - yOut`

2. `xNew = g(yNew)`

**Invariant check:**

`xNew >= g(yNew) = g(y - yOut)`
