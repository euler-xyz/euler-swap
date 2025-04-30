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

## Private Deployment

- EulerSwapFactory: 0x04C54FF83e4BC428FD1eDA2f41cdBd583A2e9cF8
- EulerSwapPeriphery: 0x64A8410D7D2ecF3Aaf32b6C3932e4586f3C42ecE

------

- EulerSwapFactory: 0xF75548aF02f1928CbE9015985D4Fcbf96d728544
- EulerSwapPeriphery: 0x813D74E832b3d9E9451d8f0E871E877edf2a5A5f
- USDT-USDT pool: 0x2bFED8dBEb8e6226a15300AC77eE9130E52410fE

------ with Uniswap hook contracts (latest)

- EulerSwap implementation: 0x0B8CD42911551882638f4C762A66570e1fAc624f
- EulerSwapFactory: 0x52177559e6430396b9A7E2176Ef33b4e4052D125
- EulerSwapPeriphery: 0x9F27Bc363DB128cdC349CA54671E6Fbe2bE194D0
- USDT-USDT pool: 0x13f627635CD96a2A75c2efBDba979172cAb2E888

## Base Dev Deployment

- EulerSwapFactory: 0x410c17c9bbcb2c69f55b450b047b8909d33e66e4
- EulerSwapPeriphery: 0x57256da76b154c8b3cff6ab816f18f48c541dbc4

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
