# EulerSwap
[Git Source](https://github.com/euler-xyz/euler-maglev/blob/d6fc4adb9f1050f1348bfff5db3603f2482ba705/src/EulerSwap.sol)

**Inherits:**
[IEulerSwap](/src/interfaces/IEulerSwap.sol/interface.IEulerSwap.md), EVCUtil


## State Variables
### curve

```solidity
bytes32 public constant curve = keccak256("EulerSwap v1");
```


### vault0

```solidity
address public immutable vault0;
```


### vault1

```solidity
address public immutable vault1;
```


### asset0

```solidity
address public immutable asset0;
```


### asset1

```solidity
address public immutable asset1;
```


### eulerAccount

```solidity
address public immutable eulerAccount;
```


### debtLimit0

```solidity
uint112 public immutable debtLimit0;
```


### debtLimit1

```solidity
uint112 public immutable debtLimit1;
```


### initialReserve0

```solidity
uint112 public immutable initialReserve0;
```


### initialReserve1

```solidity
uint112 public immutable initialReserve1;
```


### feeMultiplier

```solidity
uint256 public immutable feeMultiplier;
```


### priceX

```solidity
uint256 public immutable priceX;
```


### priceY

```solidity
uint256 public immutable priceY;
```


### concentrationX

```solidity
uint256 public immutable concentrationX;
```


### concentrationY

```solidity
uint256 public immutable concentrationY;
```


### reserve0

```solidity
uint112 public reserve0;
```


### reserve1

```solidity
uint112 public reserve1;
```


### status

```solidity
uint32 public status;
```


## Functions
### nonReentrant


```solidity
modifier nonReentrant();
```

### constructor


```solidity
constructor(Params memory params, CurveParams memory curveParams) EVCUtil(IEVault(params.vault0).EVC());
```

### swap

Optimistically sends the requested amounts of tokens to the `to`
address, invokes `uniswapV2Call` callback on `to` (if `data` was provided),
and then verifies that a sufficient amount of tokens were transferred to
satisfy the swapping curve invariant.


```solidity
function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
    external
    callThroughEVC
    nonReentrant;
```

### getReserves


```solidity
function getReserves() external view returns (uint112, uint112, uint32);
```

### EVC

Returns the address of the Ethereum Vault Connector (EVC) used by this contract.


```solidity
function EVC() external view override(EVCUtil, IEulerSwap) returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the EVC contract.|


### activate

Approves the vaults to access the EulerSwap instance's tokens, and enables
vaults as collateral. Can be invoked by anybody, and is harmless if invoked again.
Calling this function is optional: EulerSwap can be activated on the first swap.


```solidity
function activate() public;
```

### verify

Function that defines the shape of the swapping curve. Returns true iff
the specified reserve amounts would be acceptable (ie it is above and to-the-right
of the swapping curve).


```solidity
function verify(uint256 newReserve0, uint256 newReserve1) public view returns (bool);
```

### withdrawAssets


```solidity
function withdrawAssets(address vault, uint256 amount, address to) internal;
```

### depositAssets


```solidity
function depositAssets(address vault, uint256 amount) internal returns (uint256);
```

### myDebt


```solidity
function myDebt(address vault) internal view returns (uint256);
```

### myBalance


```solidity
function myBalance(address vault) internal view returns (uint256);
```

### offsetReserve


```solidity
function offsetReserve(uint112 reserve, address vault) internal view returns (uint112);
```

### f

*EulerSwap curve definition
Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18*


```solidity
function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256);
```

## Events
### EulerSwapCreated

```solidity
event EulerSwapCreated(address indexed asset0, address indexed asset1);
```

### Swap

```solidity
event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    uint112 reserve0,
    uint112 reserve1,
    address indexed to
);
```

## Errors
### Locked

```solidity
error Locked();
```

### Overflow

```solidity
error Overflow();
```

### BadParam

```solidity
error BadParam();
```

### DifferentEVC

```solidity
error DifferentEVC();
```

### AssetsOutOfOrderOrEqual

```solidity
error AssetsOutOfOrderOrEqual();
```

### CurveViolation

```solidity
error CurveViolation();
```

### DepositFailure

```solidity
error DepositFailure(bytes reason);
```

