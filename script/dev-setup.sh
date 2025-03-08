#!/bin/bash

set -e

rm -rf script/dev-ctx/
mkdir -p script/dev-ctx/{addresses,labels}/31337

forge script --rpc-url http://127.0.0.1:8545 script/DeployDev.sol --broadcast
