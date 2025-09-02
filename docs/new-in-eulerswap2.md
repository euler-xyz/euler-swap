---
title: "New in EulerSwap 2"
description: "Changelog for EulerSwap 2 release"
sidebar_position: 9
---

# Changes in EulerSwap 2

* A new Registry contract has been factored out from the Factory. Pool creators can optionally register their pools here to advertise them for solvers. The registry implements a challenge flow for people to remove incorrectly configured pools in exchange for recovering "validity bonds" posted by pool creators. 
* Separate vaults for borrowing and supplying. In some scenarios users would like to borrow from a popular liquid vault, but would prefer to deposit into a restricted escrow vault (for example).
* Asymmetric fees. In ES 1, the same fixed fee was deducted from swaps in either direction. Sometimes it makes sense to have these be different, for example if the underlying pair is a lot more liquid in one direction (perhaps it can be staked instantly, but there is a waiting period for unstaking).
* Limit orders. By taking advantage of asymmetric fees, swapping can be supported in one direction but entirely disabled in the other. This would allow you to use an ES operator as a resting limit order with partial-fill support. For example, you could be a price-maker when rebalancing a position from one collateral to another, rather than paying the spread as a price-taker.
* Swap hooks. An optional contract called a "swap hook" can be invoked prior to each swap. Swap hooks can control the fee charged for each individual swap, or reject the swap altogether. This will allow experimentation with dynamic fee mechanisms, such as arbitrage-capturing swap auctions.
* Minimum reserves. In contrast to ES 1 which always provides full-range liquidity, minimum reserves allow an LP to specify a minimum-allowed value for each of their virtual reserves. By carefully choosing these values so that real reserves are depleted at this point, LPs can provide concentrated liquidity over bounded price ranges.
* Optionally route LP fees to a different address. ES 1 always sent the LP fees to the same account that is providing the liquidity. Allowing fees to be sent elsewhere provides flexibility to contract users that implement pooled deposit models.
* Dynamic modification of pool parameters. Rather than having to create a new ES instance for each reconfiguration, curve parameters, fees, and swap hooks can now be reconfigured dynamically while preserving the address of the EulerSwap operator. Although this does somewhat reduce the cost of some reconfigurations, the primary benefit is to contract users who would like to modify curve parameters as the result of a user operation (for example a deposit into a liquidity pool). In many of these cases, it is not practical for an off-chain user to provide the salt value needed to satisfy the Uniswap4 hook address.
* Delegation of pool management. Users who want to allow a third party to manage their ES pools can install a separate management operator that has permission to change the pool parameters using the standard EVC auth mechanism. Alternatively, pool owners who wish to delegate pool configuration without granting full EVC operator permission can use a dedicated manager role in the EulerSwap contract.
* Expose creationCode accessor from the factory. This simplifies and future-proofs the off-chain logic for creating ES instances.
* isInstalled view function. Convenient way to check if a given ES instance is currently installed as an operator, rather than calling the EVC.
* Structured storage addresses with no known pre-images. It was pointed out that ES 1 did not fully conform to the recommendations related to structured storage locations (this is a purely theoretical/pedantic update).
* The periphery validates the amount of output tokens actually received, since non-EVK vaults are now allowed that could have malicious withdraw/borrow methods.
