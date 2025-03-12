# IEulerSwapPeriphery
[Git Source](https://github.com/euler-xyz/euler-maglev/blob/d6fc4adb9f1050f1348bfff5db3603f2482ba705/src/interfaces/IEulerSwapPeriphery.sol)


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

