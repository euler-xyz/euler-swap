# EulerSwap

EulerSwap is an automated market maker (AMM) that integrates with Euler [credit vaults](https://docs.euler.finance/euler-vault-kit-white-paper/) to provide deeper liquidity for swaps. When a user initiates a swap, a smart contract called an EulerSwap operator borrows the required output token using the input token as collateral. This model enables up to 40x the liquidity depth of traditional AMMs by making idle assets in Euler more efficient. Unlike traditional AMMs, which often fragment liquidity across multiple pools, EulerSwap further increases capital efficiency by allowing a single, cross-collateralised credit vault to support multiple asset pairs at once. At its core, EulerSwap uses a flexible AMM curve to optimise swap pricing, ensuring deep liquidity while maintaining market balance. By combining just-in-time liquidity, shared liquidity across pools, and customisable AMM mechanics, EulerSwap reduces inefficiencies in liquidity provision, offering deeper markets, lower costs, and greater control for liquidity providers.

For more information, refer to the [white paper](./docs/whitepaper/EulerSwap_White_Paper.pdf).

## Usage

EulerSwap comes with a comprehensive set of tests written in Solidity, which can be executed using Foundry.

To install Foundry:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. To start Foundry, run:

```sh
foundryup
```

To clone the repo:

```sh
git clone https://github.com/euler-xyz/euler-swap.git && cd euler-swap
```

## Testing

### in `default` mode

To run the tests in a `default` mode:

```sh
forge test
```

### in `coverage` mode

```sh
forge coverage
```

## Smart Contracts Documentation

```sh
forge doc --serve --port 4000
```

## Deployment Addresses

On networks where Uniswap v4 is deployed, EulerSwap is deployed using a factory variant that creates Uniswap v4 hook compatible instances. Elsewhere, the original 'OG' version of EulerSwap factory is deployed. The deployed addresses can be found in [Contract Addresses](https://docs.euler.finance/developers/contract-addresses) section of Euler docs. To check which version is deployed, call `poolManager` on the EulerSwap implementation contract (`eulerSwapV1Implementation`). If it returns zero-address then 'OG' version is deployed.

## Getting Started

The `script` folder contains scripts for deploying pools, as well as executing test trades on them. See the dedicated [README](./script/README.md)

## For Solvers

### Swaps

There are two ways to swap directly on EulerSwap: via a Uniswap V4 hook or by calling the pool’s [swap](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwap.sol#L65) function, which has the same ABI and behaviour as Uniswap V2 pools.

Additionally, the `EulerSwapPeriphery` contract provides helper functions: [swapExactIn](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwapPeriphery.sol#L8) and [swapExactOut](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwapPeriphery.sol#L21)

### Quotes

EulerSwap pools expose the [computeQuote](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwap.sol#L53) function for quoting both exact input and exact output trades. The function will revert if there is insufficient liquidity for the requested amount or if the pool has been decommissioned. If the function returns a quote, it means the trade should be executable based on the pool’s current state, but it's not guaranteed if the pool is abandoned or not maintained properly (See the **Creating and Decommissioning Pools** section).

The `EulerSwapPeriphery` contract also provides the [quoteExactInput](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwapPeriphery.sol#L32) and [quoteExactOutput](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwapPeriphery.sol#L38) helper functions

### Liquidity

Unlike traditional AMMs, EulerSwap pools do not hold token reserves directly. Instead, liquidity is provided just-in-time from the underlying Euler lending vaults. The amount that can be deposited to or withdrawn from the lending vaults depends on the current state of the EulerSwap account and various factors, such as supply and borrow caps, vault utilization, etc. This means there may be limits at any given moment on how much can be sold or bought in a trade.

These limits are directional, resulting in four distinct parameters: input and output limits for trades in each direction. The [getLimits](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwap.sol#L59) function can be used to fetch the current liquidity limits available for swapping and is also available via `EulerSwapPeriphery`.

Note that these limits are enforced by the quoting functions, which will revert if a trade exceeds them.

### Creating and Decomissioning Pools

The EulerSwap pools are created by the `EulerSwapFactory` contract, which emits a [PoolDeployed](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/EulerSwapFactory.sol#L32) event and provides functions to list existing instances.

Pools can also be uninstalled by LPs, for example during rebalancing, in which case the factory emits a [PoolUninstalled](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/EulerSwapFactory.sol#L34) event.

However, note that EulerSwap instances are installed on top of regular accounts within the Euler lending platform—they do not control these accounts. This means an LP can abandon an EulerSwap instance simply by withdrawing their position from the lending vaults. In such cases, the factory has no indication that the pool is no longer operational, but quoting functions or swap simulations will start reverting. If a pool continually fails to return quotes or reverts in simulation, it should likely be blacklisted.

## Safety

This software is experimental and is provided "as is" and "as available".

No warranties are provided and no liability will be accepted for any loss incurred through the use of this codebase.

Always include thorough tests when using EulerSwap to ensure it interacts correctly with your code.

## Known limitations

Refer to the [white paper](./docs/whitepaper/EulerSwap_White_Paper.pdf) for a list of known limitations and security considerations.

## Contributing

The code is currently in an experimental phase. Feedback or ideas for improving EulerSwap are appreciated. Contributions are welcome from anyone interested in conducting security research, writing more tests including formal verification, improving readability and documentation, optimizing, simplifying, or developing integrations.

## License

(c) 2024-2025 Euler Labs Ltd.

All rights reserved.
