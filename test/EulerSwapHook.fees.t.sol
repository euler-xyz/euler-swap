// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {EulerSwapHook} from "../src/EulerSwapHook.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager, PoolManagerDeployer} from "./utils/PoolManagerDeployer.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MinimalRouter} from "./utils/MinimalRouter.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract EulerSwapHookTest is EulerSwapTestBase {
    using StateLibrary for IPoolManager;

    EulerSwapHook public eulerSwap;

    IPoolManager public poolManager;
    PoolSwapTest public swapRouter;
    MinimalRouter public minimalRouter;

    PoolSwapTest.TestSettings public settings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

    function setUp() public virtual override {
        super.setUp();

        poolManager = PoolManagerDeployer.deploy(address(this));
        swapRouter = new PoolSwapTest(poolManager);
        minimalRouter = new MinimalRouter(poolManager);

        // set swap fee to 10 bips
        eulerSwap = createEulerSwapHook(poolManager, 60e18, 60e18, 0.001e18, 1e18, 1e18, 0.4e18, 0.85e18);
        eulerSwap.activate();

        // confirm pool was created
        assertFalse(eulerSwap.poolKey().currency1 == CurrencyLibrary.ADDRESS_ZERO);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(eulerSwap.poolKey().toId());
        assertNotEq(sqrtPriceX96, 0);
    }

    function test_SwapExactIn() public {
        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(minimalRouter), amountIn);

        bool zeroForOne = address(assetTST) < address(assetTST2);
        BalanceDelta result = minimalRouter.swap(eulerSwap.poolKey(), zeroForOne, amountIn, 0, "");
        vm.stopPrank();

        assertEq(assetTST.balanceOf(anyone), 0);
        assertEq(assetTST2.balanceOf(anyone), amountOut);

        assertEq(zeroForOne ? uint256(-int256(result.amount0())) : uint256(-int256(result.amount1())), amountIn);
        assertEq(zeroForOne ? uint256(int256(result.amount1())) : uint256(int256(result.amount0())), amountOut);
    }

    /// @dev swapping with an amount that exceeds PoolManager's ERC20 token balance will revert
    /// if the router does not pre-pay the input
    function test_swapExactIn_revertWithoutTokenLiquidity() public {
        uint256 amountIn = 1e18; // input amount exceeds PoolManager balance

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(swapRouter), amountIn);

        bool zeroForOne = address(assetTST) < address(assetTST2);
        PoolKey memory poolKey = eulerSwap.poolKey();
        vm.expectRevert();
        _swap(poolKey, zeroForOne, true, amountIn);
        vm.stopPrank();
    }

    function test_SwapExactOut() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

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
    }

    /// @dev swapping with an amount that exceeds PoolManager's ERC20 token balance will revert
    /// if the router does not pre-pay the input
    function test_SwapExactOut_revertWithoutTokenLiquidity() public {
        uint256 amountOut = 1e18;
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);

        assetTST.mint(anyone, amountIn);

        vm.startPrank(anyone);
        assetTST.approve(address(swapRouter), amountIn);
        bool zeroForOne = address(assetTST) < address(assetTST2);
        PoolKey memory poolKey = eulerSwap.poolKey();
        vm.expectRevert();
        _swap(poolKey, zeroForOne, false, amountOut);
        vm.stopPrank();
    }

    function _swap(PoolKey memory key, bool zeroForOne, bool exactInput, uint256 amount) internal {
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: exactInput ? -int256(amount) : int256(amount),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        swapRouter.swap(key, swapParams, settings, "");
    }
}
