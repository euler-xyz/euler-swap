// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {IRMTestFixed} from "evk-test/mocks/IRMTestFixed.sol";
import {Errors as EVKErrors} from "evk/EVault/shared/Errors.sol";
import {FundsLib} from "../src/libraries/FundsLib.sol";
import "evk/EVault/shared/Constants.sol" as EVKConstants;

contract DepositFailuresTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;
    address public griefer = makeAddr("griefer");

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);
    }

    function test_griefing() public monotonicHolderNAV {
        // Make a borrow to push exchange rate > 1

        eTST2.setInterestRateModel(address(new IRMTestFixed()));

        mintAndDeposit(griefer, eTST, 100e18);

        vm.prank(griefer);
        evc.enableCollateral(griefer, address(eTST));
        vm.prank(griefer);
        evc.enableController(griefer, address(eTST2));

        vm.prank(griefer);
        eTST2.borrow(1e18, griefer);
        skip(1);

        // Do a swap

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        // Honest deposit
        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        // Griefer front-runs with 1 wei deposit, which rounds down to 0 shares
        assetTST2.mint(address(this), 1);
        assetTST2.transfer(address(eulerSwap), 1);

        // Naive deposit() would fail with E_ZeroShares
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        assertEq(assetTST2.balanceOf(address(eulerSwap)), 1); // griefing transfer was untouched
    }

    function test_depositFailure() public monotonicHolderNAV {
        // Do a swap

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        // Honest deposit
        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        // Griefer front-runs with 1 wei deposit, which rounds down to 0 shares
        assetTST2.mint(address(this), 1);
        assetTST2.transfer(address(eulerSwap), 1);

        // Force deposits to fail
        eTST2.setHookConfig(address(0), EVKConstants.OP_DEPOSIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                FundsLib.DepositFailure.selector, abi.encodeWithSelector(EVKErrors.E_OperationDisabled.selector)
            )
        );
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), 0);

        assertEq(assetTST2.balanceOf(address(eulerSwap)), 1); // griefing transfer was untouched
    }

    function test_manualEnableController() public monotonicHolderNAV {
        vm.prank(holder);
        evc.enableController(holder, address(eTST));

        uint256 amountIn = 50e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        // Swap the other way to measure gas impact

        amountIn = 100e18;
        amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);

        assetTST2.mint(address(this), amountIn);
        assetTST2.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(amountOut, 0, address(this), "");
    }
}
