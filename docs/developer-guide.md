# EulerSwap Developer Guide

## Code structure

EulerSwap is split into the following main contracts:

* `EulerSwap`: Contract that is installed as an EVC operator by liquidity providers, and is also invoked by swappers in order to execute a swap.
  * `UniswapHook`: This is an internal contract used by `EulerSwap` that contains the functions required to function as a Uniswap4 hook.
* `EulerSwapFactory`: The factory contract for creating `EulerSwap` instances.
* `EulerSwapRegistry`: The registry serves as a directory for advertising and discovering active `EulerSwap` instances.
* `EulerSwapPeriphery`: Simple wrapper contract for quoting and performing swaps, while handling approvals, slippage, etc.

The above contracts depend on libraries:

* `CtxLib`: Allows access to the `EulerSwap` context: Structured storage and the instance parameters
* `FundsLib`: Moving tokens: approvals and transfers in/out
* `CurveLib`: Mathematical routines for calculating the EulerSwap curve
* `QuoteLib`: Computing quotes. This involves invoking the logic from `CurveLib`, as well as taking into account other limitations such as vault utilisation, supply caps, etc.
* `SwapLib`: Core logic for executing swaps.


## Operational flow

The following steps outline how an EulerSwap operator is created and configured:

1. Deposit initial liquidity into one or both of the underlying credit vaults to enable swaps.
1. Choose the desired pool parameters (`IEulerSwap.StaticParams` and `IEulerSwap.DynamicParams` structs) and initial state (`IEulerSwap.InitialState`).
1. Create the EulerSwap instance:
  1. [Mine](https://docs.uniswap.org/contracts/v4/guides/hooks/hook-deployment#hook-miner) a salt such that the predicted address of the EulerSwap instance will be deployed with the correct flags (required for Uniswap4 support).
  1. Install the above address as an [EVC operator](https://evc.wtf/docs/whitepaper/#operators), ensuring that any previous `EulerSwap` operators are uninstalled.
  1. Invoke `deployPool()` on the EulerSwapFactory.
1. Optional: Call the `registerPool()` method on the EulerSwapRegistry with the above instance address.




## Pool Parameters

When creating an EulerSwap instance, the pool is parameterised by two different classes of parameters:

* Static Parameters: These are immutable parameters that cannot be changed through the pool's lifetime. To save gas, these are passed as trailing calldata to EulerSwap instances.
* Dynamic Parameters: These parameters can be modified by the pool owner, and are kept in storage.

In addition, the initial state of the the reserves are provided.

### Static Parameters

* `supplyVault0` and `supplyVault1`: Addresses of vaults that should be used to store balances. Swaps will first attempt to withdraw from the corresponding input vault before doing any borrowing.
* `borrowVault0` and `borrowVault1`: Addresses of vaults that should be borrowed from once the corresponding supply vault is exhausted. These can be the same addresses as the supply vaults. If `address(0)` is provided, then any operation that causes the pool to attempt a borrow will fail.
* `eulerAccount`: The owner/holder of the liquidity. This address must install the EulerSwap instance as an [EVC operator](https://evc.wtf/docs/whitepaper/#operators).
* `feeRecipient`: The address that receives swapping fees. Use `address(0)` for them to accrue to the `eulerAccount`.
* `protocolFeeRecipient` and `protocolFee`: These control the protocol fee settings. They should be read from the EulerSwapFactory prior to creating an instance.

### Dynamic Parameters

* `equilibriumReserve0` and `equilibriumReserve1`: At equilibrium, how much "virtual reserve" of each asset should the pool consider it has. This is not necessarily the same as how much actual liquidity is available, since extra liquidity may be borrowable. Like all reserve values, these are in units of the underlying asset.
* `minReserve0` and `minReserve1`: These are the minimum values that the reserves are allowed to be reduced to. Use `0` for both if you want to support full-range liquidity. Otherwise, a non-zero value can be chosen so that the actual underlying liquidity is depleted when this level of reserve is reached. This allows an instance to provide all of its liquidity over a restricted price range.
* `priceX` and `priceY`: These form the numerator and denominator of a fraction that represents the price of the assets at the equilibrium point. This fraction must also reflect any decimal differences between the two assets.
* `concentrationX` and `concentrationY`: These control how concentrated the swap curve is on each side of the equilibirum point. The more concentrated, the smaller the price impact is for a given size trade. These are 18-scale decimal numbers between 0 and 1. A concentration of 0 means constant-product, and a concentration of 1 means constant-sum.
* `fee0` and `fee1`: The fee to be applied to the input of asset0 and asset1 respectively. These are 18-scale decimal numbers. The special value of `1e18` means that swaps in this direction are rejected. These can be overridden by the [getFee hook](#get-fee-hook).
* `expiration`: A timestamp after which swaps can no longer be performed on this pool. This is useful for pools that implement limit orders.
* `swapHookedOperations` and `swapHook`: See [Hooks](#hooks).

### Initial State

This allows the `reserve0` and `reserve1` state variables to be set to arbitrary values. In most cases these can just be set to be the same as `equilibriumReserve0` and `equilibriumReserve1`. However, if you wish for the pool to start at point on the swapping curve different from the equilibrium point, different values can be selected.

Note that in the initial configuration, these values are verified to represent a point exactly on the curve. If they are either above or below the curve, the pool deployment will fail.

### Reconfiguration

The dynamic parameters and the initial state can be changed at any time via the `reconfigure()` method. This method can be invoked by the following entities:

* The `eulerAccount` address from the static parameters.
* Any EVC operator that the `eulerAccount` has designated to perform actions on its behalf.
* A *manager* address that the `eulerAccount` has delegated by calling `setManager`. This is useful in order to give an address `reconfigure()` support without allowing it full EVC operator access.
* The `swapHook` address (allowing the [afterSwap hook](#after-swap-hook) to reconfigure).

When reconfiguring, the provided initial state reserves are not verified to be precisely on the curve. Although they may not be below the curve, they may be up and to the right, representing excess value exists in the pool that is not claimed by the EulerSwap instance. Pools should be careful to not leak value in this case, since any excess tokens can be claimed by the next swapper, even with 0 input tokens. Setting the reserve values to the same as the equilibrium reserves will never leak value in this way.



## Factory

The `EulerSwapFactory` is a permissionless contract for creating `EulerSwap` instances. Given the pool parameters and initial state, it does some basic validation, creates an instance, and invokes `activate()` on the instance, which does some additional validation and sets up its storage.

Note that the factory allows any types of vaults to be used by EulerSwap operators. Care should be taken when interacting with EulerSwap instances for this reason, since not all vault types have been designed to work correctly with `EulerSwap`. In order to limit this, swappers can choose to only use instances that have been added to the [registry](#Registry), which validates vaults according to a [perspective](#valid-vault-perspectives).

### Metaproxies

Each `EulerSwap` instance is a lightweight proxy, roughly modelled after [EIP-3448](https://eips.ethereum.org/EIPS/eip-3448). The only difference is that EIP-3448 appends the length of the metadata, whereas we don't, since it is a fixed size.

When an `EulerSwap` instance is created, the `IEulerSwap.StaticParams` struct is ABI encoded and provided as the proxy metadata. This is provided to the implementation contract as trailing calldata via `delegatecall`. This allows the static parameters to be accessed cheaply when servicing a swap, compared to if they had to be read from storage.



## Registry

The `EulerSwapRegistry` contract is an optional directory that pools can be added to. Only the creator of a pool can add it. By adding a pool to a registry, you are advertising it to solvers and aggregators. Pools in a registry are discoverable by trading pair. Although some solvers may be able to find and use pools that have not been added to any registry, others rely on a more organised and searchable directory of pools.

When adding a pool to a registry, you may be required to post a *validity bond*. This is a bond denominated in native token, the minimum value of which is set by a special registry curator. If you remove your pool from the registry, the bond will be returned to you. However, if at any time your pool is quoting swaps that cannot actually be filled, you may forfeit the bond.

There are two mechanisms for the bond to be seized:

* The registry curator may manually unregister your pool. At their discretion, they may either return the bond to the pool creator, or seize it to discourage invalid/spam registrations.
* Any user may *challenge* a pool by providing a quote that cannot be filled. If the challenge is successful, the pool is unregistered and the challenger receives the bond.

You can read the minimum required validity bond for a registry by calling the `minimumValidityBond()` method. If this value is 0, then no value is required to be sent with `registerPool()`, and pools cannot be challenged (although the curator may still manually remove them).

### Valid Vault Perspectives

The registry contract verifies that the contract instances it registers were created by the `EulerSwapFactory`. During registration, it queries the instance to determine which underlying vaults it is using, and then verifies these are acceptable by calling an `isVerified()` method on a *perspective* contract. Typically this will be a simple contract that checks that the instance was created by the Euler Vault Kit factory, however the curator may install a new perspective contract to allow additional vault-types.

### Challenges

In order to challenge a pool to retrieve the validity bond, a challenger invokes the `challengePool` method. As arguments, the challenger provides the parameters required to perform a swap on the pool: The input/output tokens, an amount, and whether the swap is exact input or exact output. The registry then performs the following:

* A quote is retrieved for this swap.
  * If this fails, the challenge is rejected.
* The swap is actually performed by taking the input tokens from the challenger. The challenger must've given appropriate token approval to the registry. In all cases, the funds will be returned to the challenger, meaning they can be sourced with a flash loan.
  * If this swap succeeds, the entire transaction is reverted (including the swap) and the challenge is rejected.
  * If the swap failed for any reason other than `E_AccountLiquidity()` or `HookError()` then the challenge is rejected. This check is necessary because some vaults can fail for other expected reasons, such as unpopulated pull oracles.
* At this point, the challenge has succeeded. The validity bond is sent to the `recipient` address provided by the challenger, and the pool is unregistered.



## Hooks

Custom behaviour can be added to an EulerSwap instance via the hook mechanism. There are two hooks, one that runs before the swap is performed (and during quoting), and one that runs after a swap has been performed.

Pool operators who want to ensure their pool remains in a registry must ensure that the hooks they install do not revert. If they do revert, they may be challenged and removed. To prevent a swap temporarily, the `getFee` hook can return `1e18` (see below).

The `swapHookedOperations` is a bitmask that controls which of the two hooks should be invoked. The `IEulerSwapHookTarget.sol` file contains 3 constants that should be bitwise OR'ed together to select which hooks should be invoked:

* `EULER_SWAP_HOOK_BEFORE_SWAP`
* `EULER_SWAP_HOOK_GET_FEE`
* `EULER_SWAP_HOOK_AFTER_SWAP`

### Before Swap Hook

This hook is invoked before the swap actually starts. No tokens will have yet been taken or sent.

The hook is invoked with a regular `call`, meaning that it may perform state-changing operations. However, it is not allowed to call back into the EulerSwap instance, because it holds a reentrancy lock.

Note that hooks which modify storage should verify the `msg.sender` is actually the expected EulerSwap pool instance, otherwise anyone could invoke the hook methods at any time and potentially cause unexpected behaviour. Alternatively, hooks may use `msg.sender` as a mapping key for their storage, so any third-party callers would be unable to touch the storage used for the EulerSwap instance(s).

### Get Fee Hook

This hook is invoked in two cases:

* When a quote is being calculated. Since quotes are performed by view methods, the getFee hook must not modify any storage in this case. To indicate this, the hook receives a `readOnly` boolean parameter.
* When a swap is about to be performed. `readOnly` will be false in this case, allowing storage to be modified.

In either case, the getFee hook should return the fee that will be required for the swap. This is a fraction scaled by 18 decimals. For example, a fee of 10% would be `0.1e18`. In addition, there are two special additional values supported:

* `1e18`: This indicates the swap is rejected.
* `type(uint64).max`: This indicates that the default fee configured in the dynamic parameters should be used instead.

The same warning about verifying `msg.sender` in the beforeSwap hook also applies.

### After Swap Hook

This hook is invoked after a swap has been performed, so it can always modify storage. It is invoked at the very end of a swapping operation, so it sees the final effects of a swap on the pool's reserves, and the underlying vaults.

If the after swap hook reverts, then the entire swap will be aborted. This can be used to perform post-swap invariant checks. For example, it could verify that borrow interest being paid is not too high. Note however that doing so may cause complications for aggregators/solvers since they cannot necessarily rely on the quotes issued by your pool to actually be executable. For this reason, pools that revert may be challenged and removed from registry, if validity bonds are posted.

While invoking the after swap hook, the EulerSwap instance's reentrancy lock is unlocked. This allows the hook to call `reconfigure()` on the instance if desired.

The same warning about verifying `msg.sender` in the beforeSwap hook also applies.
