// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IUniswapV2Callee} from "../src/interfaces/IUniswapV2Callee.sol";
// import {Test, console} from "forge-std/Test.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";
import {Maglev} from "../src/Maglev.sol";

contract UniswapV2CallTest is MaglevTestBase {
    Maglev public maglev;
    SwapCallbackTest swapCallback;

    function setUp() public virtual override {
        super.setUp();

        createMaglev(50e18, 50e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

        swapCallback = new SwapCallbackTest();
    }

    function createMaglev(
        uint112 debtLimitA,
        uint112 debtLimitB,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) internal {
        vm.prank(creator);
        maglev = new Maglev(
            getMaglevParams(debtLimitA, debtLimitB, fee),
            Maglev.CurveParams({priceX: px, priceY: py, concentrationX: cx, concentrationY: cy})
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);
    }

    function test_callback() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = periphery.quoteExactInput(address(maglev), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(maglev), amountIn);

        uint256 randomBalance = 3e18;
        vm.prank(anyone);
        swapCallback.executeSwap(maglev, 0, amountOut, abi.encode(randomBalance));
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

    function executeSwap(Maglev maglev, uint256 amountIn, uint256 amountOut, bytes calldata data) external {
        maglev.swap(amountIn, amountOut, address(this), data);
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
