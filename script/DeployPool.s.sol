// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {IEulerSwapFactory, IEulerSwap, EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {IEVC, IEulerSwap} from "../src/EulerSwap.sol";

/// @title Script to deploy new pool.
contract DeployPool is ScriptUtil {
    function run() public {
        // load wallet
        uint256 eulerAccountKey = vm.envUint("WALLET_PRIVATE_KEY");
        address eulerAccount = vm.rememberKey(eulerAccountKey);

        // load JSON file
        string memory inputScriptFileName = "DeployPool_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        EulerSwapFactory factory = EulerSwapFactory(vm.parseJsonAddress(json, ".factory"));
        IEulerSwap.Params memory poolParams = IEulerSwap.Params({
            vault0: vm.parseJsonAddress(json, ".vault0"),
            vault1: vm.parseJsonAddress(json, ".vault1"),
            eulerAccount: eulerAccount,
            protocolFeeRecipient: address(0),
            equilibriumReserve0: uint112(vm.parseJsonUint(json, ".equilibriumReserve0")),
            equilibriumReserve1: uint112(vm.parseJsonUint(json, ".equilibriumReserve1")),
            currReserve0: uint112(vm.parseJsonUint(json, ".currReserve0")),
            currReserve1: uint112(vm.parseJsonUint(json, ".currReserve1")),
            fee: vm.parseJsonUint(json, ".fee"),
            protocolFee: 0
        });
        IEulerSwap.CurveParams memory curveParams = IEulerSwap.CurveParams({
            priceX: vm.parseJsonUint(json, ".priceX"),
            priceY: vm.parseJsonUint(json, ".priceY"),
            concentrationX: vm.parseJsonUint(json, ".concentrationX"),
            concentrationY: vm.parseJsonUint(json, ".concentrationY")
        });
        bytes32 salt = bytes32(uint256(vm.parseJsonUint(json, ".salt")));

        IEVC evc = IEVC(factory.EVC());
        address predictedPoolAddress = factory.computePoolAddress(poolParams, curveParams, salt);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (eulerAccount, predictedPoolAddress, true))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: eulerAccount,
            targetContract: address(factory),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, curveParams, salt))
        });

        vm.startBroadcast(eulerAccount);
        evc.batch(items);
        vm.stopBroadcast();

        address pool = factory.poolByEulerAccount(eulerAccount);

        string memory outputScriptFileName = "DeployPool_output.json";

        string memory object;
        object = vm.serializeAddress("factory", "deployedPool", pool);

        vm.writeJson(object, string.concat(vm.projectRoot(), "/script/json/out/", outputScriptFileName));
    }
}
