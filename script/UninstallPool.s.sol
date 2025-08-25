// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {IEulerSwapFactory, IEulerSwap, EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {IEVC, IEulerSwap} from "../src/EulerSwap.sol";

/// @title Script to uninstall a pool from an account.
contract UninstallPool is ScriptUtil {
    function run() public {
        // load wallet
        uint256 eulerAccountKey = vm.envUint("WALLET_PRIVATE_KEY");
        address eulerAccount = vm.rememberKey(eulerAccountKey);

        // load JSON file
        string memory inputScriptFileName = "UninstallPool_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        EulerSwapFactory factory = EulerSwapFactory(vm.parseJsonAddress(json, ".factory"));

        IEVC evc = IEVC(factory.EVC());
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        address pool = factory.poolByEulerAccount(eulerAccount);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (eulerAccount, pool, false))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: eulerAccount,
            targetContract: address(factory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.uninstallPool, ())
        });

        vm.startBroadcast(eulerAccount);
        evc.batch(items);
        vm.stopBroadcast();
    }
}
