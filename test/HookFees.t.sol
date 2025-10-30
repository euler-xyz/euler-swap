// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {EulerSwap} from "../src/EulerSwap.sol";
import {SwapLib} from "../src/libraries/SwapLib.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager, PoolManagerDeployer} from "./utils/PoolManagerDeployer.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MinimalRouter} from "./utils/MinimalRouter.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract HookFeesTest is EulerSwapTestBase {
    using StateLibrary for IPoolManager;

    address protocolFeeRecipient = makeAddr("protocolFeeRecipient");

    EulerSwap public eulerSwap;

    IPoolManager public poolManager;
    PoolSwapTest public swapRouter;
    MinimalRouter public minimalRouter;

    PoolSwapTest.TestSettings public settings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

    function setUp() public virtual override {
        super.setUp();

        poolManager = PoolManagerDeployer.deploy(address(this));
        swapRouter = new PoolSwapTest(poolManager);
        minimalRouter = new MinimalRouter(poolManager);

        deployEulerSwap(address(poolManager));

        // set swap fee to 10 bips
        {
            (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
                getEulerSwapParams(60e18, 60e18, 1e18, 1e18, 0.4e18, 0.85e18, 0.001e18, address(0));
            IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: 60e18, reserve1: 60e18});

            eulerSwap = createEulerSwapHookFull(sParams, dParams, initialState);
        }

        // confirm pool was created
        assertFalse(eulerSwap.poolKey().currency1 == CurrencyLibrary.ADDRESS_ZERO);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(eulerSwap.poolKey().toId());
        assertNotEq(sqrtPriceX96, 0);
    }

    function test_SwapExactIn_withLpFee() public {
        int256 origNav = getHolderNAV();
        (uint112 r0, uint112 r1,) = eulerSwap.getReserves();

        uint256 amountIn = 1e18;
        uint256 amountInWithoutFee = amountIn - (amountIn * eulerSwap.getDynamicParams().fee0 / 1e18);
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(minimalRouter), amountIn);

        vm.expectEmit(true, true, true, true);
        emit SwapLib.Swap(
            address(minimalRouter),
            amountInWithoutFee,
            0,
            0,
            amountOut,
            amountIn - amountInWithoutFee,
            0,
            r0 + uint112(amountInWithoutFee),
            r1 - uint112(amountOut),
            address(poolManager)
        );

        bool zeroForOne = address(assetTST) < address(assetTST2);
        BalanceDelta result = minimalRouter.swap(eulerSwap.poolKey(), zeroForOne, amountIn, 0, "");
        vm.stopPrank();

        assertEq(assetTST.balanceOf(anyone), 0);
        assertEq(assetTST2.balanceOf(anyone), amountOut);

        assertEq(zeroForOne ? uint256(-int256(result.amount0())) : uint256(-int256(result.amount1())), amountIn);
        assertEq(zeroForOne ? uint256(int256(result.amount1())) : uint256(int256(result.amount0())), amountOut);

        // assert fees were not added to the reserves
        (uint112 r0New, uint112 r1New,) = eulerSwap.getReserves();
        if (zeroForOne) {
            assertEq(r0New, r0 + amountInWithoutFee);
            assertEq(r1New, r1 - amountOut);
        } else {
            // oneForZero, so the curve received asset1
            assertEq(r0New, r0 - amountOut);
            assertEq(r1New, r1 + amountInWithoutFee);
        }

        assertGt(getHolderNAV(), origNav + int256(amountIn - amountInWithoutFee));
    }

    function test_SwapExactIn_withLpFeeReverse() public {
        int256 origNav = getHolderNAV();
        (uint112 r0, uint112 r1,) = eulerSwap.getReserves();

        uint256 amountIn = 1e18;
        uint256 amountInWithoutFee = amountIn - (amountIn * eulerSwap.getDynamicParams().fee0 / 1e18);
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);

        assetTST2.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST2.approve(address(minimalRouter), amountIn);

        vm.expectEmit(true, true, true, true);
        emit SwapLib.Swap(
            address(minimalRouter),
            0,
            amountInWithoutFee,
            amountOut,
            0,
            0,
            amountIn - amountInWithoutFee,
            r0 - uint112(amountOut),
            r1 + uint112(amountInWithoutFee),
            address(poolManager)
        );

        bool zeroForOne = address(assetTST) < address(assetTST2);
        BalanceDelta result = minimalRouter.swap(eulerSwap.poolKey(), !zeroForOne, amountIn, 0, "");
        vm.stopPrank();

        assertEq(assetTST2.balanceOf(anyone), 0);
        assertEq(assetTST.balanceOf(anyone), amountOut);

        assertEq(!zeroForOne ? uint256(-int256(result.amount0())) : uint256(-int256(result.amount1())), amountIn);
        assertEq(!zeroForOne ? uint256(int256(result.amount1())) : uint256(int256(result.amount0())), amountOut);

        // assert fees were not added to the reserves
        (uint112 r0New, uint112 r1New,) = eulerSwap.getReserves();
        if (!zeroForOne) {
            assertEq(r0New, r0 + amountInWithoutFee);
            assertEq(r1New, r1 - amountOut);
        } else {
            // oneForZero, so the curve received asset1
            assertEq(r0New, r0 - amountOut);
            assertEq(r1New, r1 + amountInWithoutFee);
        }

        assertGt(getHolderNAV(), origNav + int256(amountIn - amountInWithoutFee));
    }

    function test_SwapExactOut_withLpFee() public {
        int256 origNav = getHolderNAV();
        (uint112 r0, uint112 r1,) = eulerSwap.getReserves();

        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        // inverse of the fee math in Periphery
        uint256 amountInWithoutFee = amountIn * (1e18 - eulerSwap.getDynamicParams().fee0) / 1e18;

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(minimalRouter), amountIn);

        bool zeroForOne = address(assetTST) < address(assetTST2);
        BalanceDelta result = minimalRouter.swap(eulerSwap.poolKey(), zeroForOne, amountIn, amountOut, "");
        vm.stopPrank();

        assertEq(assetTST.balanceOf(anyone), 0);
        assertEq(assetTST2.balanceOf(anyone), amountOut);

        assertEq(zeroForOne ? uint256(-int256(result.amount0())) : uint256(-int256(result.amount1())), amountIn);
        assertEq(zeroForOne ? uint256(int256(result.amount1())) : uint256(int256(result.amount0())), amountOut);

        // assert fees were not added to the reserves
        (uint112 r0New, uint112 r1New,) = eulerSwap.getReserves();
        if (zeroForOne) {
            assertEq(r0New, r0 + amountInWithoutFee + 1); // 1 wei of imprecision
            assertEq(r1New, r1 - amountOut);
        } else {
            // oneForZero, so the curve received asset1
            assertEq(r0New, r0 - amountOut);
            assertEq(r1New, r1 + amountInWithoutFee);
        }

        assertGt(getHolderNAV(), origNav + int256(amountIn - amountInWithoutFee));
    }
}
