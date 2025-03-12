# EulerSwapFactory
[Git Source](https://github.com/euler-xyz/euler-maglev/blob/d6fc4adb9f1050f1348bfff5db3603f2482ba705/src/EulerSwapFactory.sol)

**Inherits:**
[IEulerSwapFactory](/src/interfaces/IEulerSwapFactory.sol/interface.IEulerSwapFactory.md), EVCUtil

**Author:**
Euler Labs (https://www.eulerlabs.com/)

**Note:**
security-contact: security@euler.xyz


## State Variables
### allPools
*An array to store all pools addresses.*


```solidity
address[] public allPools;
```


### eulerAccountToPool
*Mapping between euler account and deployed pool that is currently set as operator*


```solidity
mapping(address eulerAccount => address operator) public eulerAccountToPool;
```


## Functions
### constructor


```solidity
constructor(address evc) EVCUtil(evc);
```

### deployPool

Deploy a new EulerSwap pool with the given parameters

*The pool address is deterministically generated using CREATE2 with a salt derived from
the euler account address and provided salt parameter. This allows the pool address to be
predicted before deployment.*


```solidity
function deployPool(IEulerSwap.Params memory params, IEulerSwap.CurveParams memory curveParams, bytes32 salt)
    external
    returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`IEulerSwap.Params`|Core pool parameters including vaults, account, and fee settings|
|`curveParams`|`IEulerSwap.CurveParams`|Parameters defining the curve shape including prices and concentrations|
|`salt`|`bytes32`|Unique value to generate deterministic pool address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address of the newly deployed pool|


### allPoolsLength

Get the length of `allPools` array.


```solidity
function allPoolsLength() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|`allPools` length.|


### getAllPoolsListSlice

Get a slice of the deployed pools array.


```solidity
function getAllPoolsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_start`|`uint256`|Start index of the slice.|
|`_end`|`uint256`|End index of the slice.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|An array containing the slice of the deployed pools.|


### checkEulerAccountOperators

Validates operator authorization for euler account. First checks if the account has an existing operator
and ensures it is deauthorized. Then verifies the new pool is authorized as an operator. Finally, updates the
mapping to track the new pool as the account's operator.


```solidity
function checkEulerAccountOperators(address eulerAccount, address newPool) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`eulerAccount`|`address`|The address of the euler account.|
|`newPool`|`address`|The address of the new pool.|


## Events
### PoolDeployed

```solidity
event PoolDeployed(
    address indexed asset0,
    address indexed asset1,
    address vault0,
    address vault1,
    uint256 indexed feeMultiplier,
    address eulerAccount,
    uint256 priceX,
    uint256 priceY,
    uint256 concentrationX,
    uint256 concentrationY,
    address pool
);
```

## Errors
### InvalidQuery

```solidity
error InvalidQuery();
```

### Unauthorized

```solidity
error Unauthorized();
```

### OldOperatorStillInstalled

```solidity
error OldOperatorStillInstalled();
```

### OperatorNotInstalled

```solidity
error OperatorNotInstalled();
```

