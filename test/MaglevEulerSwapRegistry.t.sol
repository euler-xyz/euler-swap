// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

// import {Test, console} from "forge-std/Test.sol";
// import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
// import {IEVault} from "evk/EVault/IEVault.sol";
import {MaglevTestBase} from "./MaglevTestBase.t.sol";
import {MaglevEulerSwap as Maglev} from "../src/MaglevEulerSwap.sol";
import {MaglevEulerSwapRegistry} from "../src/MaglevEulerSwapRegistry.sol";

contract MaglevEulerSwapRegistryTest is MaglevTestBase {
    Maglev public maglev;
    MaglevEulerSwapRegistry public registry;

    uint256 minFee = 0.0000000000001e18;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(owner);
        maglev = new Maglev(
            _getMaglevBaseParams(), Maglev.EulerSwapParams({px: 1e18, py: 1e18, cx: 0.4e18, cy: 0.85e18, fee: minFee})
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, address(maglev), true);

        vm.startPrank(owner);
        maglev.configure();
        maglev.setDebtLimit(50e18, 50e18);
        vm.stopPrank();

        vm.prank(owner);
        registry = new MaglevEulerSwapRegistry();
    }

    function testRegisterPool() public {
        uint256 allPoolsLengthBefore = registry.allPoolsLength();

        vm.prank(owner);
        registry.registerPool(address(maglev));

        uint256 allPoolsLengthAfter = registry.allPoolsLength();

        assertEq(allPoolsLengthAfter - allPoolsLengthBefore, 1);
        assertEq(registry.getPool(maglev.asset0(), maglev.asset1(), maglev.fee()), address(maglev));
        assertEq(registry.getPool(maglev.asset1(), maglev.asset0(), maglev.fee()), address(maglev));

        address[] memory poolsList = registry.getAllPoolsListSlice(0, type(uint256).max);
        assertEq(poolsList.length, 1);
        assertEq(poolsList[0], address(maglev));
        assertEq(registry.allPools(0), address(maglev));
    }

    function testRegisterPoolWhenAldreadyRegistered() public {
        vm.prank(owner);
        registry.registerPool(address(maglev));

        vm.prank(owner);
        vm.expectRevert(MaglevEulerSwapRegistry.PoolAlreadyRegistered.selector);
        registry.registerPool(address(maglev));
    }

    function testInvalidGetAllPoolsListSliceQuery() public {
        vm.expectRevert(MaglevEulerSwapRegistry.InvalidQuery.selector);
        registry.getAllPoolsListSlice(1, 0);
    }
}
