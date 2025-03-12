# EulerSwap interfaces

## **IEulerSwap interface**

### **Overview**

The `IEulerSwap` interface defines the core functionality for executing token swaps, activating the contract, and verifying the swapping curve invariant.

### **Functions**

#### `swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;`

- **description**: Optimistically sends the requested amounts of tokens to the `to` address, invokes `uniswapV2Call` callback on `to` (if `data` was provided), and then verifies that a sufficient amount of tokens were transferred to satisfy the swapping curve invariant.

#### `activate() external;`

- **description**: Approves the vaults to access the EulerSwap instance's tokens, and enables vaults as collateral. Can be invoked by anybody, and is harmless if invoked again. Calling this function is optional: EulerSwap can be activated on the first swap.

#### `verify(uint256 newReserve0, uint256 newReserve1) external view returns (bool);`

- **description**: Function that defines the shape of the swapping curve. Returns true if the specified reserve amounts would be acceptable (i.e., above and to-the-right of the swapping curve).

### **Accessors**

#### `curve() external view returns (bytes32);`

- **description**: Returns the identifier of the swapping curve.

#### `vault0() external view returns (address);`

- **description**: Returns the address of vault 0.

#### `vault1() external view returns (address);`

- **description**: Returns the address of vault 1.

#### `asset0() external view returns (address);`

- **description**: Returns the address of asset 0.

#### `asset1() external view returns (address);`

- **description**: Returns the address of asset 1.

#### `eulerAccount() external view returns (address);`

- **description**: Returns the address of the account managing EulerSwap.

#### `equilibriumReserve0() external view returns (uint112);`

- **description**: Returns the equilibrium reserve amount of asset 0.

#### `equilibriumReserve1() external view returns (uint112);`

- **description**: Returns the equilibrium reserve amount of asset 1.

#### `feeMultiplier() external view returns (uint256);`

- **description**: Returns the fee multiplier applied to transactions.

#### `getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 status);`

- **description**: Retrieves the current reserve amounts and contract status.

### **Curve accessors**

#### `priceX() external view returns (uint256);`

- **description**: Returns the marginal price of asset X in terms of asset Y at the equilibrium point.

#### `priceY() external view returns (uint256);`

- **description**: Returns the marginal price of asset Y in terms of asset X at the equilibrium point.

#### `concentrationX() external view returns (uint256);`

- **description**: Returns the liquidity concentration of asset X.

#### `concentrationY() external view returns (uint256);`

- **description**: Returns the liquidity concentration of asset Y.

---

## **IEulerSwapPeriphery interface**

### **Overview**

The `IEulerSwapPeriphery` interface provides auxiliary functions for quoting token swap amounts before execution.

### **Functions**

#### `quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);`

- **description**: Calculates how much `tokenOut` can be received for `amountIn` of `tokenIn`.

#### `quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256);`

- **description**: Calculates how much `tokenIn` is required to receive `amountOut` of `tokenOut`.

---

## **IUniswapV2Callee interface**

### **Overview**

The `IUniswapV2Callee` interface defines the callback function used for executing swaps on EulerSwap.

### **Functions**

#### `uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;`

- **description**: Callback function invoked by EulerSwap during a swap operation, allowing the contract to perform additional logic.
