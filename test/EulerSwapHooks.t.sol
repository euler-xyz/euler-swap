// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {QuoteLib} from "../src/libraries/QuoteLib.sol";
import {SwapLib} from "../src/libraries/SwapLib.sol";

contract EulerSwapHooks is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.85e18, 0.85e18);
    }

    uint64 fee0 = 0;
    uint64 fee1 = 0;
    bool expectRejectedError = false;
    address toOverride;

    function setHook(uint8 hookedOps, uint64 fee0Param, uint64 fee1Param) internal {
        PoolConfig memory pc = getPoolConfig(eulerSwap);

        pc.dParams.fee0 = fee0Param;
        pc.dParams.fee1 = fee1Param;
        pc.dParams.swapHookedOperations = hookedOps;
        pc.dParams.swapHook = address(this);

        reconfigurePool(eulerSwap, pc);
    }

    uint64 beforeSwapCounter = 0;
    uint112 bs_reserve0;
    uint112 bs_reserve1;

    function beforeSwap(bool asset0IsInput, uint112 reserve0, uint112 reserve1, bool readOnly)
        external
        returns (uint64 fee)
    {
        if (!readOnly) {
            beforeSwapCounter++;

            bs_reserve0 = reserve0;
            bs_reserve1 = reserve1;
        }

        if (asset0IsInput) return fee0;
        else return fee1;
    }

    uint64 afterSwapCounter = 0;
    uint256 as_amount0In;
    uint256 as_amount1In;
    uint256 as_amount0Out;
    uint256 as_amount1Out;
    uint256 as_fee0;
    uint256 as_fee1;
    address as_msgSender;
    address as_to;
    uint256 as_reserve0;
    uint256 as_reserve1;

    uint64 as_reconfigure_fee0;

    function afterSwap(
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 _fee0,
        uint256 _fee1,
        address msgSender,
        address to,
        uint112 reserve0,
        uint112 reserve1
    ) external {
        afterSwapCounter++;

        as_amount0In = amount0In;
        as_amount1In = amount1In;
        as_amount0Out = amount0Out;
        as_amount1Out = amount1Out;
        as_fee0 = _fee0;
        as_fee1 = _fee1;
        as_msgSender = msgSender;
        as_to = to;
        as_reserve0 = reserve0;
        as_reserve1 = reserve1;

        if (as_reconfigure_fee0 != 0) {
            EulerSwap.InitialState memory initial;

            (initial.reserve0, initial.reserve1,) = eulerSwap.getReserves(); // confirms re-entrancy lock released
            assertEq(initial.reserve0, reserve0);
            assertEq(initial.reserve1, reserve1);

            EulerSwap.DynamicParams memory p = eulerSwap.getDynamicParams();

            p.fee0 = as_reconfigure_fee0;

            // called from hook, not eulerAccount!
            eulerSwap.reconfigure(p, initial);
        }
    }

    function doSwap(bool exactIn, TestERC20 assetIn, TestERC20 assetOut, uint256 amount, uint256 expectedAmount)
        internal
    {
        uint256 amountIn;
        uint256 amountOut;

        if (expectRejectedError) vm.expectRevert(QuoteLib.SwapRejected.selector);

        if (exactIn) {
            amountIn = amount;
            amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetIn), address(assetOut), amountIn);
            if (!expectRejectedError) assertApproxEqAbs(amountOut, expectedAmount, 0.0001e18);
        } else {
            amountOut = amount;
            amountIn = periphery.quoteExactOutput(address(eulerSwap), address(assetIn), address(assetOut), amountOut);
            if (!expectRejectedError) assertApproxEqAbs(amountIn, expectedAmount, 0.0001e18);
        }

        assetIn.mint(address(this), amountIn);
        assetIn.transfer(address(eulerSwap), amountIn);

        if (expectRejectedError) vm.expectRevert(QuoteLib.SwapRejected.selector);

        address to = toOverride == address(0) ? address(this) : toOverride;

        if (assetIn == assetTST) {
            eulerSwap.swap(0, amountOut, to, "");
        } else {
            eulerSwap.swap(amountOut, 0, to, "");
        }

        assertEq(assetOut.balanceOf(to), amountOut);
    }

    // Asymmetric fees, no hooks

    function test_noHookAsymmetricFees1() public {
        setHook(0, 0.01e18, 0);
        fee0 = fee1 = 1e18; // ignored
        doSwap(true, assetTST, assetTST2, 1e18, 0.9875e18); // 1% fee from TST->TST2

        assertEq(beforeSwapCounter, 0); // didn't change
    }

    function test_noHookAsymmetricFees2() public {
        setHook(0, 0.01e18, 0);
        doSwap(true, assetTST2, assetTST, 1e18, 0.9974e18); // 0% fee from TST2->TST
    }

    function test_noHookAsymmetricFees3() public {
        setHook(0, 0, 0.01e18);
        doSwap(true, assetTST2, assetTST, 1e18, 0.9875e18); // 1% fee from TST2->TST
    }

    function test_noHookAsymmetricFees4() public {
        setHook(0, 0, 0.01e18);
        doSwap(true, assetTST, assetTST2, 1e18, 0.9974e18); // 0% fee from TST2->TST
    }

    // Before swap hooks

    function test_beforeSwapHook1() public {
        (uint112 origReserve0, uint112 origReserve1,) = eulerSwap.getReserves();

        setHook(1, 1e18, 1e18); // these fees are ignored
        fee0 = 0.01e18;

        doSwap(true, assetTST, assetTST2, 1e18, 0.9875e18); // 1% fee

        assertEq(beforeSwapCounter, 1);
        assertEq(afterSwapCounter, 0); // didn't change
        assertEq(bs_reserve0, origReserve0);
        assertEq(bs_reserve1, origReserve1);
    }

    function test_beforeSwapHook2() public {
        setHook(1, 1e18, 1e18);
        fee0 = 0.01e18;
        doSwap(true, assetTST2, assetTST, 1e18, 0.9974e18); // 0% fee (only other direction)
    }

    function test_beforeSwapHook3() public {
        setHook(1, 1e18, 1e18);
        fee1 = 0.01e18;
        doSwap(true, assetTST, assetTST2, 1e18, 0.9974e18); // 0% fee (only other direction)
    }

    function test_beforeSwapHook4() public {
        setHook(1, 1e18, 1e18);
        fee1 = 0.01e18;
        doSwap(true, assetTST2, assetTST, 1e18, 0.9875e18); // 1% fee
    }

    // Swaps rejected

    function test_swapRejected1() public {
        setHook(0, 1e18, 0e18);
        expectRejectedError = true;
        doSwap(true, assetTST, assetTST2, 1e18, 1e18);
    }

    function test_swapRejected2() public {
        setHook(0, 0.01e18, 1e18);
        doSwap(true, assetTST, assetTST2, 1e18, 0.9875e18); // 1% fee from TST->TST2
    }

    function test_swapRejected3() public {
        setHook(1, 0, 0);
        fee0 = 1e18;
        expectRejectedError = true;
        doSwap(true, assetTST, assetTST2, 1e18, 1e18);
    }

    function test_swapRejected4() public {
        setHook(1, 0, 0);
        fee1 = 1e18;
        expectRejectedError = true;
        doSwap(true, assetTST2, assetTST, 1e18, 1e18);
    }

    // After swap hooks

    function test_swapAfterhook() public {
        uint256 inpQuote = 6e18;
        uint64 fee = 0.05e18;
        setHook(2, fee, 1e18);
        toOverride = address(5678);

        assertEq(afterSwapCounter, 0);
        doSwap(true, assetTST, assetTST2, inpQuote, 5.6131e18);
        assertEq(beforeSwapCounter, 0); // only the after hook installed
        assertEq(afterSwapCounter, 1);

        (uint112 newReserve0, uint112 newReserve1,) = eulerSwap.getReserves();

        uint256 inpExpected = inpQuote * (1e18 - fee) / 1e18;

        assertEq(as_amount0In, inpExpected);
        assertEq(as_amount1In, 0);
        assertEq(as_amount0Out, 0);
        assertApproxEqAbs(as_amount1Out, 5.6131e18, 0.0001e18);
        assertApproxEqAbs(as_fee0, 6e18 * uint256(fee) / 1e18, 0.0001e18);
        assertEq(as_fee1, 0);
        assertEq(as_msgSender, address(this));
        assertEq(as_to, toOverride);
        assertEq(as_reserve0, newReserve0);
        assertEq(as_reserve1, newReserve1);
    }

    function test_swapBothHooks() public {
        setHook(3, 0, 0);

        assertEq(beforeSwapCounter, 0);
        assertEq(afterSwapCounter, 0);
        doSwap(true, assetTST, assetTST2, 1e18, 0.9974e18);
        assertEq(beforeSwapCounter, 1);
        assertEq(afterSwapCounter, 1);
    }

    function test_afterSwapReconfigure() public {
        setHook(2, 0, 0);
        as_reconfigure_fee0 = 0.077e18;

        doSwap(true, assetTST, assetTST2, 1e18, 0.9974e18);

        EulerSwap.DynamicParams memory p = eulerSwap.getDynamicParams();
        assertEq(p.fee0, 0.077e18);
    }
}
