// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVC, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20, console} from "./EulerSwapTestBase.t.sol";

contract Reconfigure is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_reconfigure() public {
        EulerSwap.InitialState memory initial;
        (initial.reserve0, initial.reserve1,) = eulerSwap.getReserves();

        EulerSwap.StaticParams memory sp = eulerSwap.getStaticParams();
        EulerSwap.DynamicParams memory p = eulerSwap.getDynamicParams();

        assertEq(p.priceX, 1e18);

        p.priceX = 2e18;

        vm.expectRevert(EulerSwap.Unauthorized.selector);
        eulerSwap.reconfigure(p, initial);

        vm.prank(sp.eulerAccount);
        eulerSwap.reconfigure(p, initial);

        {
            EulerSwap.DynamicParams memory p2 = eulerSwap.getDynamicParams();
            assertEq(p2.priceX, 2e18);
        }

        // Operator

        vm.prank(sp.eulerAccount);
        evc.setAccountOperator(sp.eulerAccount, address(1234), true);

        p.priceX = 3e18;

        vm.prank(address(1234));
        IEVC(evc).call(address(eulerSwap), sp.eulerAccount, 0, abi.encodeCall(EulerSwap.reconfigure, (p, initial)));

        {
            EulerSwap.DynamicParams memory p2 = eulerSwap.getDynamicParams();
            assertEq(p2.priceX, 3e18);
        }
    }
}
