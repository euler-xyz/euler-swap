# EulerSwapHook Audit

Through a new partnership between Euler Labs and Uniswap Foundation, the teams intend to expose EulerSwap's core logic and mechanisms via a Uniswap v4 Hook interface.

This is primarily done by inheriting `UniswapHook.sol:UniswapHook`, i.e. `EulerSwap is UniswapHook, ...`, and implementing a "custom curve" via `beforeSwap`. The implementation will allow integrators, interfaces, and aggregators, to trade on EulerSwap as-if it is any other Uniswap v4 Pool

```solidity
// assuming the EulerSwapHook was instantiated via EulerSwapFactory
PoolKey memory poolKey = PoolKey({
    currency0: currency0,
    currency1: currency1,
    fee: fee,
    tickSpacing: 1,
    hooks: IHooks(address(eulerSwapHook))
});

minimalRouter.swap(poolKey, zeroForOne, amountIn, 0);
```


## Audit Scope

The scope of audit involves a re-audit of EulerSwap, primarily `src/`:

```
├── src
│   ├── CtxLib.sol
│   ├── CurveLib.sol
│   ├── EulerSwap.sol
│   ├── EulerSwapFactory.sol
│   ├── EulerSwapPeriphery.sol
│   ├── FundsLib.sol
│   ├── MetaProxyDeployer.sol
│   ├── QuoteLib.sol
│   ├── UniswapHook.sol
```

> The interfaces are out of scope

## Notable Changes since the prior audit:

* Introduction of Uniswap v4 Hook logic
* Addition of a protocol fee
* Refactoring EulerSwap instances to delegate call into an implementation contract
* Replaced binary-search quoting, with a closed formula `fInverse()`

## Known Caveats

### Prepaid Inputs

Due to technical requirements, EulerSwapHook must take the input token from PoolManager and deposit it into Euler Vaults. It will appear that EulerSwapHook can only support input sizes of `IERC20.balanceOf(PoolManager)`. However swap routers can pre-emptively send input tokens (from user wallet to PoolManager) prior to calling `poolManager.swap` to get around this limitation.

An example `test/utils/MinimalRouter.sol` is provided as an example.

### Invalidated Salts

Uniswap v4 Hooks encode their behaviors within the address, requiring deployers to mine salts for a particular address pattern. Because constructor arguments influence the precomputed address during the salt-finding process, governance may accidentally invalidate a discovered salt by updating the protocol fee.

The EulerSwapFactory passes a protocol fee and protocol fee recipient to a EulerSwap instance (hook). If governance were modify either values between salt-discovery and EulerSwap deployment, the deployment would fail.

This scenario is unlikely to happen as we do not expect protocol fee parameters to change; as well, governance can pre-emptively warn deployers of the parameter change.
