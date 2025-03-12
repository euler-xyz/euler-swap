// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IUniswapV2Callee} from "../src/interfaces/IUniswapV2Callee.sol";
import {IEVault, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract UniswapV2CallTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;
    SwapCallbackTest swapCallback;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

        swapCallback = new SwapCallbackTest();
    }

    function test_callback() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        uint256 randomBalance = 3e18;
        vm.prank(anyone);
        swapCallback.executeSwap(eulerSwap, 0, amountOut, abi.encode(randomBalance));
        assertEq(assetTST2.balanceOf(address(swapCallback)), amountOut);
        assertEq(swapCallback.callbackSender(), address(swapCallback));
        assertEq(swapCallback.callbackAmount0(), 0);
        assertEq(swapCallback.callbackAmount1(), amountOut);
        assertEq(swapCallback.randomBalance(), randomBalance);
    }
}

contract SwapCallbackTest is IUniswapV2Callee {
    address public callbackSender;
    uint256 public callbackAmount0;
    uint256 public callbackAmount1;
    uint256 public randomBalance;

    function executeSwap(EulerSwap eulerSwap, uint256 amountIn, uint256 amountOut, bytes calldata data) external {
        eulerSwap.swap(amountIn, amountOut, address(this), data);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        randomBalance = abi.decode(data, (uint256));

        callbackSender = sender;
        callbackAmount0 = amount0;
        callbackAmount1 = amount1;
    }

    function test_avoid_coverage() public pure {
        return;
    }
}
