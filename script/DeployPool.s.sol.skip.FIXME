// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {IEulerSwapFactory, IEulerSwap, EulerSwapFactory} from "../src/EulerSwapFactory.sol";
import {IEVC, IEulerSwap} from "../src/EulerSwap.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {MetaProxyDeployer} from "../src/utils/MetaProxyDeployer.sol";

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

        address pool = factory.poolByEulerAccount(eulerAccount);
        require(
            pool == address(0), "EulerSwap pool is already installed for this account. Run the uninstall script first."
        );

        IEulerSwap.Params memory poolParams = IEulerSwap.Params({
            vault0: vm.parseJsonAddress(json, ".vault0"),
            vault1: vm.parseJsonAddress(json, ".vault1"),
            eulerAccount: eulerAccount,
            equilibriumReserve0: uint112(vm.parseJsonUint(json, ".equilibriumReserve0")),
            equilibriumReserve1: uint112(vm.parseJsonUint(json, ".equilibriumReserve1")),
            priceX: vm.parseJsonUint(json, ".priceX"),
            priceY: vm.parseJsonUint(json, ".priceY"),
            concentrationX: vm.parseJsonUint(json, ".concentrationX"),
            concentrationY: vm.parseJsonUint(json, ".concentrationY"),
            fee: vm.parseJsonUint(json, ".fee"),
            protocolFee: factory.protocolFee(),
            protocolFeeRecipient: factory.protocolFeeRecipient()
        });
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({
            currReserve0: uint112(vm.parseJsonUint(json, ".currReserve0")),
            currReserve1: uint112(vm.parseJsonUint(json, ".currReserve1"))
        });

        bytes memory creationCode =
            MetaProxyDeployer.creationCodeMetaProxy(factory.eulerSwapImpl(), abi.encode(poolParams));
        (address predictedPoolAddress, bytes32 salt) = HookMiner.find(
            address(address(factory)),
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            ),
            creationCode
        );

        IEVC evc = IEVC(factory.EVC());
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
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, initialState, salt))
        });

        vm.startBroadcast(eulerAccount);
        evc.batch(items);
        vm.stopBroadcast();

        pool = factory.poolByEulerAccount(eulerAccount);

        string memory outputScriptFileName = "DeployPool_output.json";

        string memory object;
        object = vm.serializeAddress("factory", "deployedPool", pool);

        vm.writeJson(object, string.concat(vm.projectRoot(), "/script/json/", outputScriptFileName));
    }
}
