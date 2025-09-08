// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEulerSwapCallee} from "../src/interfaces/IEulerSwapCallee.sol";
import {IEVault, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract EulerSwapCallTest is EulerSwapTestBase {
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

        uint256 randomBalance = 3e18;
        vm.prank(anyone);
        swapCallback.executeSwap(eulerSwap, assetTST, assetTST2, amountIn, 0, 0, amountOut, abi.encode(randomBalance));
        assertEq(assetTST2.balanceOf(address(swapCallback)), amountOut);
        assertEq(swapCallback.callbackSender(), address(swapCallback));
        assertEq(swapCallback.callbackAmount0(), 0);
        assertEq(swapCallback.callbackAmount1(), amountOut);
        assertEq(swapCallback.randomBalance(), randomBalance);
    }
}

contract SwapCallbackTest is IEulerSwapCallee {
    uint256 amountIn0;
    uint256 amountIn1;
    TestERC20 assetTST;
    TestERC20 assetTST2;
    address public callbackSender;
    uint256 public callbackAmount0;
    uint256 public callbackAmount1;
    uint256 public randomBalance;

    function executeSwap(
        EulerSwap eulerSwap,
        TestERC20 assetTST_,
        TestERC20 assetTST2_,
        uint256 amountIn0_,
        uint256 amountIn1_,
        uint256 amountOut0,
        uint256 amountOut1,
        bytes calldata data
    ) external {
        assetTST = assetTST_;
        assetTST2 = assetTST2_;
        amountIn0 = amountIn0_;
        amountIn1 = amountIn1_;

        eulerSwap.swap(amountOut0, amountOut1, address(this), data);
    }

    function eulerSwapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        randomBalance = abi.decode(data, (uint256));

        callbackSender = sender;
        callbackAmount0 = amount0;
        callbackAmount1 = amount1;

        if (amountIn0 > 0) {
            assetTST.mint(address(msg.sender), amountIn0);
        }

        if (amountIn1 > 0) {
            assetTST2.mint(address(msg.sender), amountIn1);
        }
    }

    function test_avoid_coverage() public pure {
        return;
    }
}
