# IEulerSwap
[Git Source](https://github.com/euler-xyz/euler-maglev/blob/d6fc4adb9f1050f1348bfff5db3603f2482ba705/src/interfaces/IEulerSwap.sol)


## Functions
### swap

Optimistically sends the requested amounts of tokens to the `to`
address, invokes `uniswapV2Call` callback on `to` (if `data` was provided),
and then verifies that a sufficient amount of tokens were transferred to
satisfy the swapping curve invariant.


```solidity
function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
```

### activate

Approves the vaults to access the EulerSwap instance's tokens, and enables
vaults as collateral. Can be invoked by anybody, and is harmless if invoked again.
Calling this function is optional: EulerSwap can be activated on the first swap.


```solidity
function activate() external;
```

### verify

Function that defines the shape of the swapping curve. Returns true iff
the specified reserve amounts would be acceptable (ie it is above and to-the-right
of the swapping curve).


```solidity
function verify(uint256 newReserve0, uint256 newReserve1) external view returns (bool);
```

### EVC

Returns the address of the Ethereum Vault Connector (EVC) used by this contract.


```solidity
function EVC() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the EVC contract.|


### curve


```solidity
function curve() external view returns (bytes32);
```

### vault0


```solidity
function vault0() external view returns (address);
```

### vault1


```solidity
function vault1() external view returns (address);
```

### asset0


```solidity
function asset0() external view returns (address);
```

### asset1


```solidity
function asset1() external view returns (address);
```

### eulerAccount


```solidity
function eulerAccount() external view returns (address);
```

### initialReserve0


```solidity
function initialReserve0() external view returns (uint112);
```

### initialReserve1


```solidity
function initialReserve1() external view returns (uint112);
```

### feeMultiplier


```solidity
function feeMultiplier() external view returns (uint256);
```

### getReserves


```solidity
function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 status);
```

### priceX


```solidity
function priceX() external view returns (uint256);
```

### priceY


```solidity
function priceY() external view returns (uint256);
```

### concentrationX


```solidity
function concentrationX() external view returns (uint256);
```

### concentrationY


```solidity
function concentrationY() external view returns (uint256);
```

## Structs
### Params

```solidity
struct Params {
    address vault0;
    address vault1;
    address eulerAccount;
    uint112 debtLimit0;
    uint112 debtLimit1;
    uint256 fee;
}
```

### CurveParams

```solidity
struct CurveParams {
    uint256 priceX;
    uint256 priceY;
    uint256 concentrationX;
    uint256 concentrationY;
}
```

