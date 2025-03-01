## Implementation of `f`

`f` (aka the "EulerSwap Function") is a parameterisable curve that defines the boundary of permissible points for EulerSwap AMMs. Points on the curve or above and to-the right are allowed, others are not.

Only formula 3 from the whitepaper is implemented in the EulerSwap core, since this can be used for both domains of the curve by mirroring the parameters. The more complicated formula 4 is a closed-form method for quoting swaps so it can be implemented in a periphery (if desired).

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

### Boundary Analysis

Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18

None of the computations for the arguments to `mulDiv` can overflow:

- Arg 1: `px * (x0 - x)`
  - Upper-bound: `1e36*(2**112 - 1) =~ 232 bits`
- Arg 2: `c * x + (1e18 - c) * x0`
  - Upper-bound: `1e18*(2**112 - 1)*2 =~ 173 bits`
- Arg 3: `x * 1e18`
  - Upper-bound: `1e18*(2**112 - 1) =~ 172 bits`

If amounts/prices are large, and we travel too far down the curve, then `mulDiv` (or the subsequent `y0` addition) could overflow because its output value cannot be represented as a `uint256`. However, these output values would never be valid anyway, because they exceed `type(uint112).max`.

To see this, consider the case where `mulDiv` fails due to overflow. This means that its result would've been greater than `2**256 - 1`. Dividing this value by the largest allowed value for `py` (`1e36`) gives approximately `2**136`, which is greater than the maximum allowed amount value of `2**112 - 1`. Both the rounding up operation and the final addition of `y0` can only further _increase_ this value. This means that all cases where `mulDiv` or the subsequent additions overflow would involve `f()` returning values that are impossible for a swapper to satisfy, so they would revert anyways.
