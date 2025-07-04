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

On networks where Uniswap v4 is deployed, EulerSwap is deployed using a factory variant that creates Uniswap v4 hook compatible instances. Elsewhere, the original 'OG' version of EulerSwap factory is deployed.

### With Uniswap v4 Hook

### Mainnet (id: 1)

```javascript
{
"eulerSwapV1Factory": "0xb013be1D0D380C13B58e889f412895970A2Cf228",
"eulerSwapV1Implementation": "0xc35a0FDA69e9D71e68C0d9CBb541Adfd21D6B117",
"eulerSwapV1Periphery": "0x208fF5Eb543814789321DaA1B5Eb551881D16b06"
}
```

### Unichain (id: 130)

```javascript
{
"eulerSwapV1Factory": "0x45b146BC07c9985589B52df651310e75C6BE066A",
"eulerSwapV1Implementation": "0xd91B0bfACA4691E6Aca7E0E83D9B7F8917989a03",
"eulerSwapV1Periphery": "0xdAAF468d84DD8945521Ea40297ce6c5EEfc7003a"
}
```

### Avalanche C-Chain (id: 43114)

```javascript
{
"eulerSwapV1Factory": "0x8A1D3a4850ed7deeC9003680Cf41b8E75D27e440",
"eulerSwapV1Implementation": "0x4F4FDeE3568aC31C46634fb2Df3FF44A156Be351",
"eulerSwapV1Periphery": "0x31F34124a37f94efd17201A1B88d5008cD444c72"
}
```

### BNB Smart Chain (id: 56)

```javascript
{
"eulerSwapV1Factory": "0x3e378e5E339DF5e0Da32964F9EEC2CDb90D28Cc7",
"eulerSwapV1Implementation": "0x16BCa43290b77409e6D1c92B929f7A09C0E4EE86",
"eulerSwapV1Periphery": "0xa8826Bb29f875Db4c4b482463961776390774525"
}
```

### Base (id: 8453)

```javascript
{
"eulerSwapV1Factory": "0xf0CFe22d23699ff1B2CFe6B8f706A6DB63911262",
"eulerSwapV1Implementation": "0x3Ce63C16CB719a0c755DA25cd5dD35170A00424f",
"eulerSwapV1Periphery": "0x18e5F5C1ff5e905b32CE860576031AE90E1d1336"
}
```

### Without Uniswap v4 Hook

### Sonic (id: 146)

```javascript
{
"eulerSwapV1Factory": "0x94041db6deC15f79666B07846c13e6F7341b4a80",
"eulerSwapV1Implementation": "0x4D57F54582b333E4184A3cF40d1D61FE6D70c35D",
"eulerSwapV1Periphery": "0xb2237DC86B184e50Fc2F8b028B2b7AE192ef2566"
}
```

### Swellchain (id: 1923)

```javascript
{
"eulerSwapV1Factory": "0x976dd85654B3b2f9fb66280ACE30Cab7C81a2130",
"eulerSwapV1Implementation": "0x3620dAb0DB5595479a4D5408595D48FbE48CeA2A",
"eulerSwapV1Periphery": "0x34932C04c3d27c2BD7aCd0B5d203bfd65a17f481"
}
```

### Berachain (id: 80094)

```javascript
{
"eulerSwapV1Factory": "0xD14c95dc228E8851F63d9b83A0001F4D021B5DFf",
"eulerSwapV1Implementation": "0x0e05d236cb6c350935751A73e834A13111998e3c",
"eulerSwapV1Periphery": "0x46F951278f52f4798542C51BfB8Df1c165199150"
}
```

### BOB (id: 60808)

```javascript
{
"eulerSwapV1Factory": "0xE25B3cdA6fccAcbD794aEA64eE1B496d7b441644",
"eulerSwapV1Implementation": "0x334eac29ffAc27E6BC3484A738DAf520359698F0",
"eulerSwapV1Periphery": "0x199cC7C8606088bc22D82CDae2D7EE7F5F99ec9F"
}
```

## Getting Started

The `script` folder contains scripts for deploying pools, as well as executing test trades on them. See the dedicated [README](./script/README.md)

## For Solvers

### Swaps

There are two ways to swap directly on EulerSwap: via a Uniswap V4 hook or by calling the pool’s [swap](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwap.sol#L65) function, which has the same ABI and behaviour as Uniswap V2 pools.

Additionally, the `EulerSwapPeriphery` contract provides helper functions: [swapExactIn](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwapPeriphery.sol#L8) and [swapExactOut](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwapPeriphery.sol#L21)

### Quotes

EulerSwap pools expose the [computeQuote](https://github.com/euler-xyz/euler-swap/blob/1f73f5cb07f2e64e8c9815076749574b1b54e204/src/interfaces/IEulerSwap.sol#L53) function for quoting both exact input and exact output trades. The function will revert if there is insufficient liquidity for the requested amount or if the pool has been decommissioned. If the function returns a quote, it means the trade is executable based on the pool’s current state (assuming the pool is operational—see the **Creating and Decommissioning Pools** section).

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
