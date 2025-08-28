// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {
    IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, EulerSwapRegistry, TestERC20
} from "./EulerSwapTestBase.t.sol";

contract CustodianTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        vm.deal(holder, 0.123e18);
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);
    }

    function test_custodianUnregisterPool() public {
        assertEq(holder.balance, 0);
        assertEq(eulerSwapRegistry.poolsLength(), 1);

        vm.expectRevert(EulerSwapRegistry.Unauthorized.selector);
        eulerSwapRegistry.custodianUnregisterPool(address(eulerSwap));

        vm.prank(custodian);
        eulerSwapRegistry.custodianUnregisterPool(address(eulerSwap));

        assertEq(holder.balance, 0.123e18);
        assertEq(eulerSwapRegistry.poolsLength(), 0);

        // Verify that unregister still works:

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), false);
        vm.prank(holder);
        eulerSwapRegistry.unregisterPool();
    }

    function test_transferCustodian() public {
        assertEq(eulerSwapRegistry.custodian(), custodian);

        vm.expectRevert(EulerSwapRegistry.Unauthorized.selector);
        eulerSwapRegistry.transferCustodian(address(6666));

        vm.prank(custodian);
        eulerSwapRegistry.transferCustodian(address(7777));

        assertEq(eulerSwapRegistry.custodian(), address(7777));
    }

    function test_minimumValidityBond() public {
        assertEq(eulerSwapRegistry.validityBond(address(eulerSwap)), 0.123e18);
        assertEq(eulerSwapRegistry.minimumValidityBond(), 0);

        vm.expectRevert(EulerSwapRegistry.Unauthorized.selector);
        eulerSwapRegistry.setMinimumValidityBond(0.1e18);

        vm.prank(custodian);
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
}
