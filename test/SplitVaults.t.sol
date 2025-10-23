// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20, IRMTestDefault} from "./EulerSwapTestBase.t.sol";

contract SplitVaults is EulerSwapTestBase {
    IEVault public eTST_alt;
    IEVault public eTST2_alt;

    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        // Setup alt vaults

        eTST_alt = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTST2_alt = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST2), address(oracle), unitOfAccount))
        );

        eTST_alt.setHookConfig(address(0), 0);
        eTST_alt.setInterestRateModel(address(new IRMTestDefault()));
        eTST_alt.setMaxLiquidationDiscount(0.2e4);

        eTST2_alt.setHookConfig(address(0), 0);
        eTST2_alt.setInterestRateModel(address(new IRMTestDefault()));
        eTST2_alt.setMaxLiquidationDiscount(0.2e4);

        eTST_alt.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);
        eTST2_alt.setLTV(address(eTST), 0.9e4, 0.9e4, 0);

        oracle.setPrice(address(eTST_alt), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2_alt), unitOfAccount, 1e18);

        mintAndDeposit(depositor, eTST_alt, 50e18);
        mintAndDeposit(depositor, eTST2_alt, 50e18);

        installAltBorrowVaults(eTST_alt, eTST2_alt);
    }

    function installAltBorrowVaults(IEVault bv0, IEVault bv1) internal {
        // Setup EulerSwap
        uint112 reserve0 = 60e18;
        uint112 reserve1 = 60e18;

        (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
            getEulerSwapParams(reserve0, reserve1, 1e18, 1e18, 0.85e18, 0.85e18, 0, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: reserve0, reserve1: reserve1});

        sParams.borrowVault0 = address(bv0);
        sParams.borrowVault1 = address(bv1);

        eulerSwap = createEulerSwapFull(sParams, dParams, initialState);
    }

    modifier isSwappable() {
        _;
        verifyInLimitSwappable(eulerSwap, assetTST, assetTST2);
        verifyInLimitSwappable(eulerSwap, assetTST2, assetTST);
        verifyOutLimitSwappable(eulerSwap, assetTST, assetTST2);
        verifyOutLimitSwappable(eulerSwap, assetTST2, assetTST);
    }

    function test_splitVault_swap() public isSwappable {
        assertEq(eTST.balanceOf(holder), 10e18);
        assertEq(eTST2.balanceOf(holder), 10e18);

        {
            uint256 amountIn = 20e18;
            uint256 amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);
            eulerSwap.swap(0, amountOut, address(this), "");
        }

        assertEq(eTST.balanceOf(holder), 30e18);
        assertEq(eTST2.balanceOf(holder), 0);

        assertEq(eTST2.debtOf(holder), 0);
        assertApproxEqAbs(eTST2_alt.debtOf(holder), 8.725e18, 0.001e18);

        {
            uint256 amountIn = 40e18;
            uint256 amountOut =
                periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);

            assetTST2.mint(address(this), amountIn);
            assetTST2.transfer(address(eulerSwap), amountIn);
            eulerSwap.swap(amountOut, 0, address(this), "");
        }

        assertEq(eTST.balanceOf(holder), 0e18);
        assertApproxEqAbs(eTST2.balanceOf(holder), 31.274e18, 0.001e18);

        assertEq(eTST.debtOf(holder), 0);
        assertApproxEqAbs(eTST_alt.debtOf(holder), 9.809e18, 0.001e18);
    }

    function expandReserves() internal {
        PoolConfig memory pc = getPoolConfig(eulerSwap);
        pc.initialState.reserve0 = pc.dParams.equilibriumReserve0 = 1000e18;
        pc.initialState.reserve1 = pc.dParams.equilibriumReserve1 = 1000e18;
        reconfigurePool(eulerSwap, pc);
    }

    function validateOutputSwapPossible(TestERC20 assetIn, TestERC20 assetOut, uint256 amountOut)
        internal
        isSwappable
    {
        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetIn), address(assetOut), amountOut);

        assetIn.mint(address(this), amountIn);
        assetIn.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetOut.balanceOf(address(this)), amountOut);
    }

    function test_splitVault_limits() public isSwappable {
        expandReserves();

        (, uint256 outLimit) = periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
        assertEq(outLimit, 60e18 - 1); // 10 deposited in eTST2, 50 borrowable in eTST2_alt

        validateOutputSwapPossible(assetTST, assetTST2, 60e18);
    }

    function test_splitVault_borrowCap() public isSwappable {
        expandReserves();

        eTST2_alt.setCaps(0, uint16(6.0e2 << 6) | 18);

        (, uint256 outLimit) = periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
        assertEq(outLimit, 16e18 - 1); // 10 to withdraw from TST2, 6 available in eTST2_alt to borrow

        validateOutputSwapPossible(assetTST, assetTST2, 3e18);
    }

    function test_splitVault_supplyVaultCashLimited() public isSwappable {
        expandReserves();

        {
            vm.startPrank(depositor);
            eTST2.withdraw(100e18, address(depositor), address(depositor));
            evc.enableCollateral(depositor, address(eTST));
            evc.enableController(depositor, address(eTST2));
            eTST2.borrow(7e18, address(1));
            vm.stopPrank();
        }

        (, uint256 outLimit) = periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
        assertEq(outLimit, 3e18 - 1); // not enough cash for holder to withdraw balance in TST2

        validateOutputSwapPossible(assetTST, assetTST2, 3e18 - 1);
    }

    function test_splitVault_nullBorrowVault0() public isSwappable {
        installAltBorrowVaults(IEVault(address(0)), eTST2_alt);
    }

    function test_splitVault_nullBorrowVault1() public isSwappable {
        installAltBorrowVaults(eTST_alt, IEVault(address(0)));
    }

    function test_splitVault_nullBorrowVaultBoth() public isSwappable {
        installAltBorrowVaults(IEVault(address(0)), IEVault(address(0)));
    }
}
