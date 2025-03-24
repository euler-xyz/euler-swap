# Swapping scenarios

The swap function operates within two potential domains for `x`:

- **Domain 1:** `0 < x < x0`
- **Domain 2:** `x > x0`

We allow swaps in or out of both the `X` and `Y` assets. Depending on the swap, the system may either remain in the current domain or transition to the other domain.

## Function definitions

- `y = f(x)`: Function that maps `x` to `y` in domain 1.
- `x = fInverse(y)`: Inverse function that maps `y` to `x` in domain 1.
- `x = g(y)`: Function that maps `y` to `x` in domain 2.
- `y = gInverse(x)`: Function that maps `x` to `y` in domain 2.

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

**Note:** We know the new x-coordinate is fixed, because the user has swapped that much X in. If we overestimate the y-coordinate, we simply give the user a worse swap -- less Y out -- than if we had used a more precise method.

### 1b. Swap `xIn` and move to domain 2

**Calculation steps:**

1. `xNew = x + xIn`

2. `yNew = gInverse(xNew)`

**Invariant check:**

`xNew >= g(yNew) = g(gInverse(xNew)) = g(gInverse(x + xIn))`

**Note:** We know the new x-coordinate is fixed, because the user has swapped that much X in. If we overestimate the y-coordinate, we simply give the user a worse swap -- less Y out -- than if we had used a more precise method.

### 2. Swap `yIn` and remain in domain 1

**Calculation steps:**

1. `yNew = y + yIn`

2. `xNew = fInverse(yNew)`

**Invariant check:**

`yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y + yIn))`

**Note:** We know the new y-coordinate is real, because the user has swapped that much Y in. If we overestimate the x-coordinate, we simply give them a worse quote -- less X out -- than if we had a more precise method.

When we do y --> x = fInverse(y) --> yCalc = f(x), that means our new y-coordinate may be slightly smaller the the original.

### 3. Swap `xOut` and remain in domain 1

**Calculation steps:**

1. `xNew = x - xOut`

2. `yNew = f(xNew)`

**Invariant check:**

`yNew >= f(xNew) = f(x - xOut)`

**Note:** We know the new x-coordinate is real, because the user has swapped that much X out. If we overestimate the y-coordinate, we simply give them a worse quote -- require more Y in than is really needed -- than if we had a more precise method. Once the trade happens, we will be on or above the curve due to an excess of Y.

### 4a. Swap `yOut` and remain in domain 1

**Calculation steps:**

1. `yNew = y - yOut`

2. `xNew = fInverse(yNew)`

**Invariant check:**

`yNew >= f(xNew) = f(fInverse(yNew)) = f(fInverse(y - yOut))`

**Note:** We know the new y-coordinate is real, because the user has swapped that much Y out. If we overestimate the x-coordinate, we simply give them a worse quote -- require more X in than is really needed -- than if we had a more precise method.

### 4b. Swap `yOut` and move to domain 2

**Calculation steps:**

1. `yNew = y - yOut`

2. `xNew = g(yNew)`

**Invariant check:**

`xNew >= g(yNew) = g(y - yOut)`

**Note:** We know the new y-coordinate is real, because the user has swapped that much Y out. If we overestimate the x-coordinate, we simply give them a worse quote -- require more X in than is really needed -- than if we had a more precise method.

## Starting in domain 2

### 5. Swap `xIn` and remain in domain 2

**Calculation steps:**

1. `xNew = x + xIn`

2. `yNew = gInverse(xNew)`

**Invariant check:**

`xNew >= g(yNew) = g(gInverse(xNew)) = g(gInverse(x + xIn))`

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

2. `yNew = gInverse(xNew)`

**Invariant check:**

`xNew >= g(yNew) = g(gInverse(xNew)) = g(gInverse(x - xOut))`

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
