// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";
import {MinimalRouter} from "../test/utils/MinimalRouter.sol";
import {ScriptUtil} from "./ScriptUtil.s.sol";

// from the output of SwapExactInV4.s.sol, swap the tokens back to the original token
contract SwapBackV4 is ScriptUtil {
    using SafeERC20 for IERC20;

    MinimalRouter public minRouter = MinimalRouter(0x43292c68390e9c30Fe1ebB9db904914f2aD7D075);

    function run() public {
        // load wallet
        uint256 swapperKey = vm.envUint("WALLET_PRIVATE_KEY");
        address swapperAddress = vm.rememberKey(swapperKey);

        // load JSON file
        string memory inputScriptFileName = "SwapExactIn_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        EulerSwap pool = EulerSwap(vm.parseJsonAddress(json, ".pool"));
        address previousTokenIn = vm.parseJsonAddress(json, ".tokenIn");

        PoolKey memory poolKey = pool.poolKey();

        // tokenIn from the previous swap becomes the output now
        bool zeroForOne = Currency.unwrap(poolKey.currency0) != previousTokenIn;
        (uint256 amountIn, Currency inputCurrency) = Currency.unwrap(poolKey.currency0) == previousTokenIn
            ? (poolKey.currency1.balanceOf(swapperAddress), poolKey.currency1)
            : (poolKey.currency0.balanceOf(swapperAddress), poolKey.currency0);

        vm.startBroadcast(swapperAddress);

        IERC20(Currency.unwrap(inputCurrency)).forceApprove(address(minRouter), amountIn);

        minRouter.swap(poolKey, zeroForOne, amountIn, 0, "");

        vm.stopBroadcast();
    }
}
