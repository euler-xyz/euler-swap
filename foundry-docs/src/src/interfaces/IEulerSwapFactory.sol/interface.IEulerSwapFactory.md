# IEulerSwapFactory
[Git Source](https://github.com/euler-xyz/euler-maglev/blob/d6fc4adb9f1050f1348bfff5db3603f2482ba705/src/interfaces/IEulerSwapFactory.sol)


## Functions
### deployPool


```solidity
function deployPool(IEulerSwap.Params memory params, IEulerSwap.CurveParams memory curveParams, bytes32 salt)
    external
    returns (address);
```

### allPools


```solidity
function allPools(uint256 index) external view returns (address);
```

### allPoolsLength


```solidity
function allPoolsLength() external view returns (uint256);
```

### getAllPoolsListSlice


```solidity
function getAllPoolsListSlice(uint256 start, uint256 end) external view returns (address[] memory);
```

