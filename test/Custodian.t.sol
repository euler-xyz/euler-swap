// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {
    IEVC,
    IEVault,
    IEulerSwap,
    EulerSwapTestBase,
    EulerSwap,
    EulerSwapRegistry,
    TestERC20
} from "./EulerSwapTestBase.t.sol";

contract CuratorTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        vm.deal(holder, 0.123e18);
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);
    }

    function test_curatorUnregisterPool() public {
        assertEq(holder.balance, 0);
        assertEq(eulerSwapRegistry.poolsLength(), 1);

        vm.expectRevert(EulerSwapRegistry.Unauthorized.selector);
        eulerSwapRegistry.curatorUnregisterPool(address(eulerSwap), address(0));

        vm.prank(curator);
        eulerSwapRegistry.curatorUnregisterPool(address(eulerSwap), address(0));

        assertEq(holder.balance, 0.123e18);
        assertEq(eulerSwapRegistry.poolsLength(), 0);

        // Verify that unregister still works:

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), false);
        vm.prank(holder);
        eulerSwapRegistry.unregisterPool();
    }

    function test_curatorUnregisterPoolSeize() public {
        vm.prank(curator);
        eulerSwapRegistry.curatorUnregisterPool(address(eulerSwap), address(6543));

        assertEq(holder.balance, 0);
        assertEq(address(6543).balance, 0.123e18);
        assertEq(eulerSwapRegistry.poolsLength(), 0);
    }

    function test_transferCurator() public {
        assertEq(eulerSwapRegistry.curator(), curator);

        vm.expectRevert(EulerSwapRegistry.Unauthorized.selector);
        eulerSwapRegistry.transferCurator(address(6666));

        vm.prank(curator);
        eulerSwapRegistry.transferCurator(address(7777));

        assertEq(eulerSwapRegistry.curator(), address(7777));
    }

    function test_minimumValidityBond() public {
        assertEq(eulerSwapRegistry.validityBond(address(eulerSwap)), 0.123e18);
        assertEq(eulerSwapRegistry.minimumValidityBond(), 0);

        vm.expectRevert(EulerSwapRegistry.Unauthorized.selector);
        eulerSwapRegistry.setMinimumValidityBond(0.1e18);

        vm.prank(curator);
        eulerSwapRegistry.setMinimumValidityBond(0.2e18);

        assertEq(eulerSwapRegistry.minimumValidityBond(), 0.2e18);

        vm.deal(holder, 0.15e18);
        expectInsufficientValidityBondRevert = true;
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);

        vm.deal(holder, 0.2e18);
        expectInsufficientValidityBondRevert = false;
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);

        assertEq(eulerSwapRegistry.validityBond(address(eulerSwap)), 0.2e18);
    }

    function test_bondsSubAccount() public {
        (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
            getEulerSwapParams(1000e18, 1000e18, 1e18, 1e18, 0.85e18, 0.85e18, 0, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: 1000e18, reserve1: 1000e18});

        sParams.eulerAccount = address(uint160(holder) ^ 1);

        vm.deal(holder, 0.123e18);
        eulerSwap = createEulerSwapFull(sParams, dParams, initialState);

        assertEq(holder.balance, 0);

        vm.prank(holder);
        evc.setAccountOperator(sParams.eulerAccount, address(eulerSwap), false);
        vm.prank(holder);
        IEVC(evc).call(
            address(eulerSwapRegistry), sParams.eulerAccount, 0, abi.encodeCall(EulerSwapRegistry.unregisterPool, ())
        );

        assertEq(holder.balance, 0.123e18);
    }
}
