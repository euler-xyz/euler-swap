// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {EulerSwapRegistry} from "../src/EulerSwapRegistry.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {EulerSwapProtocolFeeConfig} from "../src/EulerSwapProtocolFeeConfig.sol";
import {EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapManagement} from "../src/EulerSwapManagement.sol";

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
        address protocolFeeAdmin = vm.parseJsonAddress(json, ".protocolFeeAdmin");
        address validVaultPerspective = vm.parseJsonAddress(json, ".validVaultPerspective");
        address curator = vm.parseJsonAddress(json, ".curator");

        vm.startBroadcast(deployerAddress);

        address eulerSwapProtocolFeeConfig = address(new EulerSwapProtocolFeeConfig(evc, protocolFeeAdmin));
        address eulerSwapManagementImpl = address(new EulerSwapManagement(evc));
        address eulerSwapImpl =
            address(new EulerSwap(evc, eulerSwapProtocolFeeConfig, poolManager, eulerSwapManagementImpl));
        address eulerSwapFactory = address(new EulerSwapFactory(evc, eulerSwapImpl));
        new EulerSwapRegistry(evc, eulerSwapFactory, validVaultPerspective, curator);
        new EulerSwapPeriphery();
        vm.stopBroadcast();
    }
}
