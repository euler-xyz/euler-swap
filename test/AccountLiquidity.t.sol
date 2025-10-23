// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract CollateralSwap is EulerSwapTestBase {
    IEVault public eTST_alt;
    IEVault public eTST2_alt;

    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        // Alt vaults

        eTST_alt = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );

        eTST2_alt = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST2), address(oracle), unitOfAccount))
        );

        // Sets up a position and pushes account into health violation

        eTST.setLTV(address(eTST2), 0, 0, 0);
        eTST2.setLTV(address(eTST), 0, 0, 0);
        eTST.setLTV(address(eTST3), 0, 0, 0);

        // Set new LTVs
        eTST3.setLTV(address(eTST), 0.9e4, 0.9e4, 0);
        eTST3.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);

        // Mint another 40 of the collateral assets (50 total in each)
        mintAndDeposit(holder, eTST, 40e18);
        mintAndDeposit(holder, eTST2, 40e18);

        // Borrow 80 TST3
        vm.startPrank(holder);

        evc.enableCollateral(holder, address(eTST));
        evc.enableCollateral(holder, address(eTST2));
        evc.enableController(holder, address(eTST3));

        eTST3.borrow(80e18, address(0xdead)); // burning simulates a looped position

        vm.stopPrank();

        oracle.setPrice(address(assetTST), unitOfAccount, 0.001e18);
        oracle.setPrice(address(eTST), unitOfAccount, 0.001e18);
    }

    function test_violation() public {
        // Would fail if EulerSwap wasn't calling isCollateralEnabled() first, because enableCollateral()
        // performs an accountStatusCheck.
        eulerSwap = createEulerSwap(49e18, 49e18, 0, 1e18, 1e18, 0.9e18, 0.9e18);
    }

    function test_violation2() public {
        // However, a different vault does require enabling collateral, so this fails with E_AccountLiquidity

        uint112 reserve0 = 60e18;
        uint112 reserve1 = 60e18;

        (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
            getEulerSwapParams(reserve0, reserve1, 1e18, 1e18, 0.85e18, 0.85e18, 0, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: reserve0, reserve1: reserve1});

        sParams.supplyVault0 = address(eTST_alt);

        expectAccountLiquidityRevert = true;
        eulerSwap = createEulerSwapFull(sParams, dParams, initialState);
    }

    function test_violation3() public {
        // Unless the borrow vault of the other asset is disabled, then no collateral enabling is required.

        uint112 reserve0 = 60e18;
        uint112 reserve1 = 60e18;

        (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
            getEulerSwapParams(reserve0, reserve1, 1e18, 1e18, 0.85e18, 0.85e18, 0, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: reserve0, reserve1: reserve1});

        sParams.supplyVault0 = address(eTST_alt);
        sParams.borrowVault1 = address(0);

        eulerSwap = createEulerSwapFull(sParams, dParams, initialState);
    }

    // Next 2 tests are same as previous 2, but reversed assets

    function test_violation4() public {
        // However, a different vault does require enabling collateral, so this fails with E_AccountLiquidity

        uint112 reserve0 = 60e18;
        uint112 reserve1 = 60e18;

        (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
            getEulerSwapParams(reserve0, reserve1, 1e18, 1e18, 0.85e18, 0.85e18, 0, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: reserve0, reserve1: reserve1});

        sParams.supplyVault1 = address(eTST2_alt);

        expectAccountLiquidityRevert = true;
        eulerSwap = createEulerSwapFull(sParams, dParams, initialState);
    }

    function test_violation5() public {
        // Unless the borrow vault of the other asset is disabled, then no collateral enabling is required.

        uint112 reserve0 = 60e18;
        uint112 reserve1 = 60e18;

        (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
            getEulerSwapParams(reserve0, reserve1, 1e18, 1e18, 0.85e18, 0.85e18, 0, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: reserve0, reserve1: reserve1});

        sParams.supplyVault1 = address(eTST2_alt);
        sParams.borrowVault0 = address(0);

        eulerSwap = createEulerSwapFull(sParams, dParams, initialState);
    }
}
