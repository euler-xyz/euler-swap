// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";

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
        address factory = vm.parseJsonAddress(json, ".factory");

        vm.startBroadcast(deployerAddress);

        new EulerSwapFactory(evc, factory);
        new EulerSwapPeriphery();

        vm.stopBroadcast();
    }
}
