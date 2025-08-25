// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, EulerSwapFactory, TestERC20} from "./EulerSwapTestBase.t.sol";

contract CustodianTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        vm.deal(holder, 0.123e18);
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);
    }

    function test_custodianUninstallPool() public {
        assertEq(holder.balance, 0);
        assertEq(eulerSwapFactory.poolsLength(), 1);

        vm.expectRevert(EulerSwapFactory.Unauthorized.selector);
        eulerSwapFactory.custodianUninstallPool(address(eulerSwap));

        vm.prank(custodian);
        eulerSwapFactory.custodianUninstallPool(address(eulerSwap));

        assertEq(holder.balance, 0.123e18);
        assertEq(eulerSwapFactory.poolsLength(), 0);

        // Verify that uninstall still works:

        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), false);
        vm.prank(holder);
        eulerSwapFactory.uninstallPool();
    }

    function test_transferCustodian() public {
        assertEq(eulerSwapFactory.custodian(), custodian);

        vm.expectRevert(EulerSwapFactory.Unauthorized.selector);
        eulerSwapFactory.transferCustodian(address(6666));

        vm.prank(custodian);
        eulerSwapFactory.transferCustodian(address(7777));

        assertEq(eulerSwapFactory.custodian(), address(7777));
    }

    function test_minimumValidityBond() public {
        assertEq(eulerSwapFactory.validityBond(address(eulerSwap)), 0.123e18);
        assertEq(eulerSwapFactory.minimumValidityBond(), 0);

        vm.expectRevert(EulerSwapFactory.Unauthorized.selector);
        eulerSwapFactory.setMinimumValidityBond(0.1e18);

        vm.prank(custodian);
        eulerSwapFactory.setMinimumValidityBond(0.2e18);

        assertEq(eulerSwapFactory.minimumValidityBond(), 0.2e18);

        vm.deal(holder, 0.15e18);
        expectInsufficientValidityBondRevert = true;
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);

        vm.deal(holder, 0.2e18);
        expectInsufficientValidityBondRevert = false;
        eulerSwap = createEulerSwap(1000e18, 1000e18, 0, 1e18, 1e18, 0.9999e18, 0.9999e18);

        assertEq(eulerSwapFactory.validityBond(address(eulerSwap)), 0.2e18);
    }
}
