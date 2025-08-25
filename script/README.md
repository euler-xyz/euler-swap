# Forge scripts

Every script takes inputs via a `ScriptName_input.json` file inside the json directory.

Before running the scripts, please make sure to fill the `.env` file following the `.env.example`. The main env variables for the script to succefully run, are `WALLET_PRIVATE_KEY` and the `NETWORK_RPC_URL`.

After filling the `.env` file, make sure to run: `source .env` in your terminal.

## Deploy new pool
- Fill the `DeployPool_input.json` file with the needed inputs.
- The `eulerAccount` will be derived from the private key provided in `.env`. The account's position on Euler should be already set up.
- Run `forge script ./script/DeployPool.s.sol --rpc-url network_name --broadcast --slow`, replacing `network_name` to match `_RPC_URL` environment variable (e.g. if running through `MAINNET_RPC_URL` replace `network_name` with `mainnet`)
- The deployed pool address will be recorded in `./scripts/json/DeployPool_output.json` file

## Exact in swap

- Fill the `SwapExactIn_input.json` file with the needed inputs.
- Run `forge script ./script/SwapExactIn.s.sol --rpc-url network_name --broadcast --slow`, replacing `network_name` to match `_RPC_URL` environment variable (e.g. if running through `MAINNET_RPC_URL` replace `network_name` with `mainnet`)

## Uninstall pool

- Fill the `UninstallPool_input.json` file with the factory address.
- Run `forge script ./script/UninstallPool.s.sol --rpc-url network_name --broadcast --slow`, replacing `network_name` to match `_RPC_URL` environment variable (e.g. if running through `MAINNET_RPC_URL` replace `network_name` with `mainnet`)

## Deploy protocol

- Fill the `DeployProtocol_input.json` file with the needed inputs.
- Run `forge script ./script/DeployProtocol.s.sol --rpc-url network_name --broadcast --slow`, replacing `network_name` to match `_RPC_URL` environment variable (e.g. if running through `MAINNET_RPC_URL` replace `network_name` with `mainnet`)
