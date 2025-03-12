# EulerSwapPeriphery
[Git Source](https://github.com/euler-xyz/euler-maglev/blob/d6fc4adb9f1050f1348bfff5db3603f2482ba705/src/EulerSwapPeriphery.sol)

**Inherits:**
[IEulerSwapPeriphery](/src/interfaces/IEulerSwapPeriphery.sol/interface.IEulerSwapPeriphery.md)


## Functions
### swapExactIn

Swap `amountIn` of `tokenIn` for `tokenOut`, with at least `amountOutMin` received.


```solidity
function swapExactIn(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
    external;
```

### swapExactOut

Swap `amountOut` of `tokenOut` for `tokenIn`, with at most `amountInMax` paid.


```solidity
function swapExactOut(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMax)
    external;
```

### quoteExactInput

How much `tokenOut` can I get for `amountIn` of `tokenIn`?


```solidity
function quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn)
    external
    view
    returns (uint256);
```

### quoteExactOutput

How much `tokenIn` do I need to get `amountOut` of `tokenOut`?


```solidity
function quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut)
    external
    view
    returns (uint256);
```

### swap

*Internal function to execute a token swap through EulerSwap*


```solidity
function swap(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`eulerSwap`|`address`|The EulerSwap contract address to execute the swap through|
|`tokenIn`|`address`|The address of the input token being swapped|
|`tokenOut`|`address`|The address of the output token being received|
|`amountIn`|`uint256`|The amount of input tokens to swap|
|`amountOut`|`uint256`|The amount of output tokens to receive|


### computeQuote

*Computes the quote for a swap by applying fees and validating state conditions*

*Validates:
- EulerSwap operator is installed
- Token pair is supported
- Sufficient reserves exist
- Sufficient cash is available*


```solidity
function computeQuote(IEulerSwap eulerSwap, address tokenIn, address tokenOut, uint256 amount, bool exactIn)
    internal
    view
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`eulerSwap`|`IEulerSwap`|The EulerSwap contract to quote from|
|`tokenIn`|`address`|The input token address|
|`tokenOut`|`address`|The output token address|
|`amount`|`uint256`|The amount to quote (input amount if exactIn=true, output amount if exactIn=false)|
|`exactIn`|`bool`|True if quoting for exact input amount, false if quoting for exact output amount|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The quoted amount (output amount if exactIn=true, input amount if exactIn=false)|


### binarySearch

Binary searches for the output amount along a swap curve given input parameters

*General-purpose routine for binary searching swapping curves.
Although some curves may have more efficient closed-form solutions,
this works with any monotonic curve.*


```solidity
function binarySearch(
    IEulerSwap eulerSwap,
    uint112 reserve0,
    uint112 reserve1,
    uint256 amount,
    bool exactIn,
    bool asset0IsInput
) internal view returns (uint256 output);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`eulerSwap`|`IEulerSwap`|The EulerSwap contract to search the curve for|
|`reserve0`|`uint112`|Current reserve of asset0 in the pool|
|`reserve1`|`uint112`|Current reserve of asset1 in the pool|
|`amount`|`uint256`|The input or output amount depending on exactIn|
|`exactIn`|`bool`|True if amount is input amount, false if amount is output amount|
|`asset0IsInput`|`bool`|True if asset0 is being input, false if asset1 is being input|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`output`|`uint256`|The calculated output amount from the binary search|


### fInverse

Computes the inverse of the `f()` function for the EulerSwap liquidity curve.

*Solves for `x` given `y` using the quadratic formula derived from the liquidity curve:
x = (-b + sqrt(b^2 + 4ac)) / 2a
Utilises mulDiv to avoid overflow and ensures precision with upward rounding.*

**Notes:**
- precision: Uses rounding up to maintain precision in all calculations.

- safety: FullMath handles potential overflow in the b^2 computation.

- requirement: Input `y` must be strictly greater than `y0`; otherwise, the function will revert.


```solidity
function fInverse(uint256 y, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
    external
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`y`|`uint256`|The y-coordinate input value (must be greater than `y0`).|
|`px`|`uint256`|Price factor for the x-axis (scaled by 1e18, between 1e18 and 1e36).|
|`py`|`uint256`|Price factor for the y-axis (scaled by 1e18, between 1e18 and 1e36).|
|`x0`|`uint256`|Reference x-value on the liquidity curve (≤ 2^112 - 1).|
|`y0`|`uint256`|Reference y-value on the liquidity curve (≤ 2^112 - 1).|
|`c`|`uint256`|Curve parameter shaping liquidity concentration (scaled by 1e18, between 0 and 1e18).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|x The computed x-coordinate on the liquidity curve.|


## Errors
### UnsupportedPair

```solidity
error UnsupportedPair();
```

### OperatorNotInstalled

```solidity
error OperatorNotInstalled();
```

### InsufficientReserves

```solidity
error InsufficientReserves();
```

### InsufficientCash

```solidity
error InsufficientCash();
```

### AmountOutLessThanMin

```solidity
error AmountOutLessThanMin();
```

### AmountInMoreThanMax

```solidity
error AmountInMoreThanMax();
```

