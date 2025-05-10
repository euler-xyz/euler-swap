# EulerSwap architecture

## Overview

EulerSwap is an automated market maker (AMM) that integrates with Euler credit vaults to provide deeper liquidity for swaps.

Each EulerSwap instance is a lightweight smart contract that functions as an [EVC operator](https://evc.wtf/docs/whitepaper/#operators) while implementing a highly customizable AMM curve to determine swap output amounts.

When a user initiates a swap, the EulerSwap operator can borrow the required output token using the input token as collateral. The operator’s internal AMM curve governs the exchange rate, ensuring deep liquidity over short timeframes while maintaining a balance between collateral and debt over the long term.

Swapping can be performed by invoking the EulerSwap instance, either through a Uniswap2-compatible `swap()` function or as a [Uniswap4 hook](https://docs.uniswap.org/contracts/v4/concepts/hooks).

## Code structure

EulerSwap is split into the following main contracts:

- `EulerSwap`: Contract that is installed as an EVC operator by liquidity providers, and is also invoked by swappers in order to execute a swap.
  - `UniswapHook`: The functions required so that the EulerSwap instance can function as a Uniswap4 hook.
- `EulerSwapFactory`: Factory contract for creating `EulerSwap` instances and for querying existing instances.
- `EulerSwapPeriphery`: This is a wrapper contract for quoting and performing swaps, while handling approvals, slippage, etc.

The above contracts depend on libraries:

- `CtxLib`: Allows access to the `EulerSwap` context: Structured storage and the instance parameters
- `FundsLib`: Moving tokens: approvals and transfers in/out
- `CurveLib`: Mathematical routines for calculating the EulerSwap curve
- `QuoteLib`: Computing quotes. This involves invoking the logic from `CurveLib`, as well as taking into account other limitations such as vault utilisation, supply caps, etc.

And some utilities:

- `MetaProxyDeployer`: Deploys EIP-3448-style proxies.
- `ProtocolFee`: The factory stores protocol fee parameters that will affect subsequently created `EulerSwap` instances. These can be changed by an owner.

## Operational flow

The following steps outline how an EulerSwap operator is created and configured:

1. Deposit initial liquidity into one or both of the underlying credit vaults to enable swaps.
1. Choose the desired pool parameters (`IEulerSwap.Params` struct). The `protocolFee` and `protocolFeeRecipient` must be read from the factory.
1. [Mine](https://docs.uniswap.org/contracts/v4/guides/hooks/hook-deployment#hook-miner) a salt such that the predicted address of the `EulerSwap` instance will be deployed with the correct flags.
1. Install the above address as an EVC operator, ensuring that any previous `EulerSwap` operators are uninstalled.
1. Invoke `deployPool()` on the EulerSwap factory.

## Metaproxies

Each `EulerSwap` instance is a lightweight proxy, roughly modelled after [EIP-3448](https://eips.ethereum.org/EIPS/eip-3448). The only difference is that EIP-3448 appends the length of the metadata, whereas we don't, since it is a fixed size.

When an `EulerSwap` instance is created, the `IEulerSwap.Params` struct is ABI encoded and provided as the proxy metadata. This is provided to the implementation contract as trailing calldata via `delegatecall`. This allows the parameters to be accessed cheaply when servicing a swap, compared to if they had to be read from storage.

## Curve Parameters

Traditional AMMs hold dedicated reserves of each of the supported tokens, which inherently limit the sizes of swaps that can be serviced. For example, if an AMM has 100 units of a token available, there is no possible price that can convince it to send more than 100 units.

Since EulerSwap does not have dedicated reserves, its swapping limits must be defined in another way. This is accomplished by having the EulerSwap operator define an abstract curve. The domain of this curve defines the swap limits, which can be considered the virtual reserves.

The abstract curve is centred on an _equilibrium point_. This is parameterised by two equilibrium reserves values. These specify the magnitude of the virtual reserves, and are effectively hard limits on the supported swap sizes. They are often equal, but do not necessarily have to be (for instance, if the two vaults have asymmetric LTVs).

At the equilibrium point, the marginal swap price is defined by the ratio of two parameters `priceX` and `priceY`. Generally operators will choose the price ratio at equilibrium to be the asset's pegged price, or the wider market price. The prices should also compensate for a difference in token decimals, if any.

Finally, the curve is parameterised by two **concentration factors** between `0` and `1`. Each corresponds to the portion of the curve to the left or right of the equilibrium point. These factors control the shape of each side of the curve (to the left of the equilibrium point, and to the right). These parameters change the curve shape according to a blend of constant product and constant sum. The closer to `0` the more the curve resembles a constant product, and the closer to `1`, constant sum.

In most cases (except with concentration factor of `1`), virtual reserves can never be fully depleted. The limits can only be approached asymptotically.

Generally it is expected that arbitrage will favour returning the reserves to the equilbrium point. The price and the convex constant-product-like curve shape encourages this. If the price at equilibrium is accurate then the equilbrium point always represents the point of minimum NAV for the operator, and this point is arbitrage-free.

## Initial State

The curve as parameterised above is an abstract geometric shape. In order to actually make use of it, you must install it on an account that already has some existing conditions. For example, it may already have a borrow, or it may have unequal deposits in the two vaults.

To be as flexible as possible, EulerSwap allows you to specify the **current reserves** when you are instantiating a pool.

If the current state of the account is where you wish the equilbrium point to be, then you should make the current reserves the same as the equilibrium reserves. Otherwise, the current reserves can be offset (take from one side and give to the other) to specify a new equilibrium point that swapping activity should take you to.

Note that there may be a race condition when removing one swap operator and installing another. In between when you've calculated the current reserves and when you've actually created and installed the new operator, a swap may occur that modifies the account state. To avoid this, a wrapper contract should be used that calculates the current reserves. Or, more simply, just verifies that the account state was as observed by the operator and otherwise reverts.

## Fees

Swapping fees are charged by requiring the swapper to pay slightly more of the input token than is required by the curve parameters. This extra amount is simply directly deposited into the vaults on behalf of the EulerSwap account. This means that it has the effect of increasing the account's NAV, but does not change the shape of the curve itself. The curve is always static, per EulerSwap instance.

When an EulerSwap instance is created, a **protocol fee** parameter may be installed by the factory. This portion of the collected fees are routed to a protocol fee recipient. An administrator of the factory can change the the protocol fee and recipient for future created EulerSwap instances, although previously created instances will not be updated retroactively.

## Reserve desynchronisation

The EulerSwap contract tracks the current reserves in storage. After a swap, the amount of received tokens is added to the current reserves, and the amount of sent tokens subtracted. Since the reserves are not allowed to go negative, this implies a hard limit on the swap sizes.

While these reserves track the state of the world as influenced by swaps, they can get out-of-sync with the actual account for various reasons:

- Interest can be accrued, either increasing or decreasing the account's NAV.
- Swap fees are not tracked, and instead increase the account's NAV.
- The account could be liquidated.
- The account owner could manually add or remove funds, repay loans, etc.

In order to correct any desynchronisation, the EulerSwap operator should be uninstalled and a new, updated one installed instead.

## getLimits

Although the virtual reserves specify a hard limit for swaps, there may be other implicit limits that are even lower:

- The vaults have high utilisation and cannot service large borrows or withdrawals
- The vaults have supply and/or borrow caps
- The operator may have been uninstalled

There is a function `getLimits` that can take these into account. This function itself is an upper-bound and the values it returns may not be swappable either, in particular if the curve shape does not allow it. However, it makes a best effort and this function can be used to rapidly exclude pools that are definitely unable to service a given size swap.

## Swapper Security

When swapping with an EulerSwap instance, users should always make sure that they received the desired amount of output tokens in one of two ways:

- Actually checking your output token balances before and after and making sure they increased by an amount to satisfy slippage.
- Ensure that the EulerSwap code is a trusted instance that will send the specified output amount or revert if not possible. This can be done by making sure an instance was created by a trusted factory.

In particular, note that the periphery does not perform either of these checks, so if you use the periphery for swapping, you should ensure that you only interact with EulerSwap instances created by a known-good factory.

## Liquidation Considerations

It is important for market makers running EulerSwap instances to parameterise their curve in such a way as to ensure that swaps cannot drive their Euler account towards liquidation. EulerSwap account owners are also responsible for monitoring the health of their vaults and should take proactive steps if their collateral accrues bad debt or drops in value—since this can happen independently of swap activity.

This is important, because if another position in the same collateral vault is liquidated and leaves behind bad debt, the value
of the shared collateral used for liquidity could drop. This would affect the effective LTV of all positions using that
vault, including those managed by the EulerSwap AMM. An attacker could exploit this situation by then initiating a swap that pushes the AMM's position right up to the liquidation threshold, leveraging the degraded collateral value caused by unrelated bad debt.
