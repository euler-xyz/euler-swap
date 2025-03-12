# Forge scripts

Every script takes inputs via a `ScriptName_input.json` file inside the json directory.

Before running the scripts, please make sure to fill the `.env` file following the `.env.example`. The main env variables for the script to succefully run, are `WALLET_PRIVATE_KEY` and the `NETWORK_RPC_URL`.

After filling the `.env` file, make sure to run: `source .env` in your terminal.

## Deploy protocol

- Fill the `DeployProtocol_input.json` file with the needed inputs.
- Run `forge script ./script/DeployProtocol.s.sol --rpc-url network_name --broadcast --slow`

## Deploy new pool

- Fill the `DeployPool_input.json` file with the needed inputs.
- In pool deployment, the `eulerAccount` address is the deployer address, so we derive the address from the attached private key in the `.env` file.
- Run `forge script ./script/DeployPool.s.sol --rpc-url network_name --broadcast --slow`

## Exact in swap

- Fill the `SwapExactIn_input.json` file with the needed inputs.
- Run `forge script ./script/SwapExactIn.s.sol --rpc-url network_name --broadcast --slow`

