// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {EulerSwapRegistry} from "../src/EulerSwapRegistry.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {EulerSwap} from "../src/EulerSwap.sol";

/// @title Script to deploy EulerSwapFactory & EulerSwapPeriphery.
contract DeployProtocol is ScriptUtil {
    function run() public {
        // load wallet
        uint256 deployerKey = vm.envUint("WALLET_PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerKey);

        // load JSON file
        string memory inputScriptFileName = "DeployProtocol_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        address evc = vm.parseJsonAddress(json, ".evc");
        address poolManager = vm.parseJsonAddress(json, ".poolManager");
        address evkFactory = vm.parseJsonAddress(json, ".evkFactory");
        address feeOwner = vm.parseJsonAddress(json, ".feeOwner");
        address feeRecipientSetter = vm.parseJsonAddress(json, ".feeRecipientSetter");
        address validVaultPerspective = vm.parseJsonAddress(json, ".validVaultPerspective");
        address custodian = vm.parseJsonAddress(json, ".custodian");

        vm.startBroadcast(deployerAddress);

        address eulerSwapImpl = address(new EulerSwap(evc, poolManager));
        address eulerSwapFactory = address(new EulerSwapFactory(evc, eulerSwapImpl, feeOwner, feeRecipientSetter));
        new EulerSwapRegistry(evc, eulerSwapFactory, validVaultPerspective, custodian);
        new EulerSwapPeriphery();
        vm.stopBroadcast();
    }
}
