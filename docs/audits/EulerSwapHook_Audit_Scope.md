# EulerSwapHook Audit

Through a new partnership between Euler Labs and Uniswap Foundation, the teams intend to expose EulerSwap's core logic and mechanisms via a Uniswap v4 Hook interface.

This is primarily done by inheriting `EulerSwap.sol:EulerSwap`, i.e. `EulerSwapHook is EulerSwap, BaseHook`, and implementing a "custom curve" via `beforeSwap`. The implementation will allow integrators, interfaces, and aggregators, to trade on EulerSwap as-if it is any other Uniswap v4 Pool

```solidity
// assuming the EulerSwapHook was instantiated via EulerSwapFactory
PoolKey memory poolKey = PoolKey({
    currency0: currency0,
    currency1: currency1,
    fee: fee,
    tickSpacing: 60,
    hooks: IHooks(address(eulerSwapHook))
});

minimalRouter.swap(poolKey, zeroForOne, amountIn, 0);
```


## Audit Scope

The scope of audit involves the code-diff introduced by [PR #48](https://github.com/euler-xyz/euler-swap/pull/48/files). **As of Apr 1st, 2025, the diff is subject to change but will be code-complete by the audit start time.**

Major Changes will include:

* Replacing `binarySearch` quoting algorithm with a closed-form formula
* Implementing a protocol fee, as a percentage of LP fees, enacted by governance

As for the files in scope, only files from `src/` should be considered:

```
├── src
│   ├── EulerSwapFactory.sol
│   ├── EulerSwapHook.sol
│   └── utils
│       └── HookMiner.sol
```

## Known Caveats

### Prepaid Inputs

Due to technical requirements, EulerSwapHook must take the input token from PoolManager and deposit it into Euler Vaults. It will appear that EulerSwapHook can only support input sizes of `IERC20.balanceOf(PoolManager)`. However swap routers can pre-emptively send input tokens (from user wallet to PoolManager) prior to calling `poolManager.swap` to get around this limitation.

An example `test/utils/MinimalRouter.sol` is provided as an example.