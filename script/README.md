# Forge scripts

Every script takes inputs via a `ScriptName_input.json` file inside the json directory.

Before running the scripts, please make sure to fill the `.env` file following the `.env.example`. The main env variables for the script to succefully run, are `WALLET_PRIVATE_KEY` and the `NETWORK_RPC_URL`.

After filling the `.env` file, make sure to run: `source .env` in your terminal.

## Deploy protocol

- Fill the `DeployProtocol_input.json` file with the needed inputs.
- Run `forge script ./script/DeployProtocol.s.sol --rpc-url network_name --broadcast --slow`, replacing `network_name` to match `_RPC_URL` environment variable (e.g. if running through `MAINNET_RPC_URL` replace `network_name` with `mainnet`)

## Deployments

These are temporary deployments for testing. The official EulerSwap instances will be deployed by the EVK periphery infrastructure.

### Base

    EulerSwapFactory: 0xd7c9ec4925e5d95d341a169e8d7275e92b064b74
    EulerSwapRegistry: 0x93c4d4909fdc3b0651374f1160ec2aed4960d82c
    EulerSwapPeriphery: 0x18f0e5f802937447f49ea5e8faebb454c5c74c71
