// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";

import {ScriptUtil} from "./ScriptUtil.s.sol";

contract SwapExactIn is ScriptUtil {
    using SafeERC20 for IERC20;

    function run() public {
        // load wallet
        uint256 swapperKey = vm.envUint("WALLET_PRIVATE_KEY");
        address swapperAddress = vm.rememberKey(swapperKey);

        // load JSON file
        string memory inputScriptFileName = "SwapExactIn_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        EulerSwapPeriphery periphery = EulerSwapPeriphery(vm.parseJsonAddress(json, ".periphery"));
        EulerSwap pool = EulerSwap(vm.parseJsonAddress(json, ".pool"));
        address tokenIn = vm.parseJsonAddress(json, ".tokenIn");
        address tokenOut = vm.parseJsonAddress(json, ".tokenOut");
        uint256 amountIn = vm.parseJsonUint(json, ".amountIn");

        uint256 amountOutMin = periphery.quoteExactInput(address(pool), tokenIn, tokenOut, amountIn);

        vm.startBroadcast(swapperAddress);

        IERC20(tokenIn).forceApprove(address(periphery), amountIn);

        periphery.swapExactIn(address(pool), tokenIn, tokenOut, amountIn, swapperAddress, amountOutMin, 0);

        vm.stopBroadcast();
    }
}
