// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {EulerSwap} from "../src/EulerSwap.sol";
import {UniswapHook} from "../src/UniswapHook.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager, PoolManagerDeployer} from "./utils/PoolManagerDeployer.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/src/test/PoolDonateTest.sol";
import {MinimalRouter} from "./utils/MinimalRouter.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

contract HookSwapsTest is EulerSwapTestBase {
    using StateLibrary for IPoolManager;

    EulerSwap public eulerSwap;

    IPoolManager public poolManager;
    PoolSwapTest public swapRouter;
    MinimalRouter public minimalRouter;
    PoolModifyLiquidityTest public liquidityManager;
    PoolDonateTest public donateRouter;

    PoolSwapTest.TestSettings public settings = PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

    function setUp() public virtual override {
        super.setUp();

        poolManager = PoolManagerDeployer.deploy(address(this));
        swapRouter = new PoolSwapTest(poolManager);
        minimalRouter = new MinimalRouter(poolManager);
        liquidityManager = new PoolModifyLiquidityTest(poolManager);
        donateRouter = new PoolDonateTest(poolManager);

        deployEulerSwap(address(poolManager));

        {
            (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
                getEulerSwapParams(60e18, 60e18, 1e18, 1e18, 0.4e18, 0.85e18, 0, address(0));
            IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: 60e18, reserve1: 60e18});

            eulerSwap = createEulerSwapHookFull(sParams, dParams, initialState);
        }

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

    function test_hookPermissions() public view {
        Hooks.Permissions memory perms = eulerSwap.getHookPermissions();

        assertTrue(perms.beforeInitialize);
        assertTrue(perms.beforeAddLiquidity);
        assertTrue(perms.beforeSwap);
        assertTrue(perms.beforeSwapReturnDelta);
        assertTrue(perms.beforeDonate);

        assertFalse(perms.afterInitialize);
        assertFalse(perms.afterAddLiquidity);
        assertFalse(perms.beforeRemoveLiquidity);
        assertFalse(perms.afterRemoveLiquidity);
        assertFalse(perms.afterSwap);
        assertFalse(perms.afterDonate);
        assertFalse(perms.afterSwapReturnDelta);
        assertFalse(perms.afterAddLiquidityReturnDelta);
        assertFalse(perms.afterRemoveLiquidityReturnDelta);
    }

    /// @dev adding liquidity as a concentrated liquidity position will revert
    function test_revertAddConcentratedLiquidity() public {
        assetTST.mint(anyone, 10000e18);
        assetTST2.mint(anyone, 10000e18);

        vm.startPrank(anyone);
        assetTST.approve(address(liquidityManager), 1e18);
        assetTST2.approve(address(liquidityManager), 1e18);

        PoolKey memory poolKey = eulerSwap.poolKey();

        // hook intentionally reverts to prevent v3-CLAMM positions
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(eulerSwap),
                IHooks.beforeAddLiquidity.selector,
                abi.encodeWithSelector(BaseHook.HookNotImplemented.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        liquidityManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({tickLower: -10, tickUpper: 10, liquidityDelta: 1000, salt: bytes32(0)}),
            ""
        );
        vm.stopPrank();
    }

    /// @dev initializing a new pool on an existing eulerswap instance will revert
    function test_revertSubsequentInitialize() public {
        PoolKey memory newPoolKey = eulerSwap.poolKey();
        newPoolKey.currency0 = CurrencyLibrary.ADDRESS_ZERO;

        // hook intentionally reverts to prevent subsequent initializations
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(eulerSwap),
                IHooks.beforeInitialize.selector,
                abi.encodeWithSelector(BaseHook.HookNotImplemented.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        poolManager.initialize(newPoolKey, 79228162514264337593543950336);
    }

    /// @dev revert on donations as they are irrecoverable if they were supported
    function test_revertDonate(uint256 amount0, uint256 amount1) public {
        PoolKey memory poolKey = eulerSwap.poolKey();

        // hook intentionally reverts to prevent irrecoverable donations
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(eulerSwap),
                IHooks.beforeDonate.selector,
                abi.encodeWithSelector(BaseHook.HookNotImplemented.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        donateRouter.donate(poolKey, amount0, amount1, "");
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
