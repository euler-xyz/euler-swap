// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {
    IEVault,
    IEulerSwap,
    EulerSwapTestBase,
    EulerSwap,
    EulerSwapProtocolFeeConfig,
    TestERC20
} from "./EulerSwapTestBase.t.sol";
import {SwapLib} from "../src/libraries/SwapLib.sol";

contract FeesTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.9e18, 0.9e18);
    }

    function test_fees_exactIn() public monotonicHolderNAV {
        int256 origNav = getHolderNAV();
        uint256 fee = 0.05e18;

        // No fees

        uint256 amountInNoFees = 1e18;
        uint256 amountOutNoFees =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountInNoFees);
        assertApproxEqAbs(amountOutNoFees, 0.9983e18, 0.0001e18);

        // With fees: Increase input amount so that corresponding output amount matches

        eulerSwap = createEulerSwap(60e18, 60e18, uint64(fee), 1e18, 1e18, 0.9e18, 0.9e18);

        uint256 amountIn = amountInNoFees * 1e18 / (1e18 - fee);
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, amountOutNoFees, 1); // Same except for possible rounding down by 1

        // Actually execute swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        // Pulling out one extra reverts...

        vm.expectRevert(SwapLib.CurveViolation.selector);
        eulerSwap.swap(0, amountOut + MAX_QUOTE_ERROR + 1, address(this), "");

        // Just right:

        eulerSwap.swap(0, amountOut, address(this), "");

        // Swapper received their quoted amount:

        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        // eulerSwap instance is empty:

        assertEq(assetTST.balanceOf(address(eulerSwap)), 0);
        assertEq(assetTST2.balanceOf(address(eulerSwap)), 0);

        // Holder's NAV increased by fee amount, plus slightly extra because we are not at curve equilibrium point

        uint256 protocolFeesCollected = assetTST.balanceOf(address(0));

        assertGt(getHolderNAV() + int256(protocolFeesCollected), origNav + int256(amountIn - amountInNoFees));
        assertEq(eTST.balanceOf(address(holder)), 10e18 + amountIn - protocolFeesCollected);
        assertEq(eTST2.balanceOf(address(holder)), 10e18 - amountOut);
    }

    function test_fees_exactOut() public monotonicHolderNAV {
        int256 origNav = getHolderNAV();
        uint256 fee = 0.05e18;

        // No fees

        uint256 amountOut = 1e18;
        uint256 amountInNoFees =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountInNoFees, 1.0017e18, 0.0001e18);

        // With fees: Increase input amount so output amount stays same

        eulerSwap = createEulerSwap(60e18, 60e18, uint64(fee), 1e18, 1e18, 0.9e18, 0.9e18);

        uint256 amountIn =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amountOut);
        assertApproxEqAbs(amountIn, amountInNoFees * 1e18 / (1e18 - fee), 1); // Same except for possible rounding up by 1

        // Actually execute swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        // Pulling out one extra reverts...

        vm.expectRevert(SwapLib.CurveViolation.selector);
        eulerSwap.swap(0, amountOut + MAX_QUOTE_ERROR + 1, address(this), "");

        // Just right:

        eulerSwap.swap(0, amountOut, address(this), "");

        // Swapper received their quoted amount:

        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        // eulerSwap instance is empty:

        assertEq(assetTST.balanceOf(address(eulerSwap)), 0);
        assertEq(assetTST2.balanceOf(address(eulerSwap)), 0);

        // Holder's NAV increased by fee amount, plus slightly extra because we are not at curve equilibrium point

        uint256 protocolFeesCollected = assetTST.balanceOf(address(0));

        assertGt(getHolderNAV() + int256(protocolFeesCollected), origNav + int256(amountIn - amountInNoFees));
        assertEq(eTST.balanceOf(address(holder)), 10e18 + amountIn - protocolFeesCollected);
        assertEq(eTST2.balanceOf(address(holder)), 10e18 - amountOut);
    }

    function test_altFeeRecipient() public {
        uint64 fee = 0.05e18;

        // No fees

        uint256 amountInNoFees = 1e18;
        uint256 amountOutNoFees =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountInNoFees);
        assertApproxEqAbs(amountOutNoFees, 0.9983e18, 0.0001e18);

        // With fees: Increase input amount so that corresponding output amount matches

        {
            (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
                getEulerSwapParams(60e18, 60e18, 1e18, 1e18, 0.9e18, 0.9e18, fee, address(54321));
            IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: 60e18, reserve1: 60e18});

            eulerSwap = createEulerSwapFull(sParams, dParams, initialState);
        }

        uint256 amountIn = amountInNoFees * 1e18 / (1e18 - fee);
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, amountOutNoFees, 1); // Same except for possible rounding down by 1

        // Actually execute swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        eulerSwap.swap(0, amountOut, address(this), "");

        // Swapper received their quoted amount:
        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        // Alt fee recipient received their fees
        assertEq(assetTST.balanceOf(address(54321)), amountIn - amountInNoFees);
    }

    function test_fees_protocolFees_swap() public {
        uint256 fee = 0.05e18;
        uint256 protocolFee = 0.1e18;

        {
            (IEulerSwap.StaticParams memory sParams, IEulerSwap.DynamicParams memory dParams) =
                getEulerSwapParams(60e18, 60e18, 1e18, 1e18, 0.9e18, 0.9e18, uint64(fee), address(54321));
            IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({reserve0: 60e18, reserve1: 60e18});

            eulerSwap = createEulerSwapFull(sParams, dParams, initialState);
        }

        vm.prank(protocolFeeAdmin);
        protocolFeeConfig.setDefault(address(8888), uint64(protocolFee));

        uint256 amountInNoFees = 1e18;

        uint256 amountIn = amountInNoFees * 1e18 / (1e18 - fee);
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

        // Actually execute swap

        assetTST.mint(address(this), amountIn);
        assetTST.transfer(address(eulerSwap), amountIn);

        eulerSwap.swap(0, amountOut, address(this), "");

        // Swapper received their quoted amount:
        assertEq(assetTST2.balanceOf(address(this)), amountOut);

        uint256 feeAmount = amountIn - amountInNoFees;
        uint256 protocolFeeAmount = feeAmount * protocolFee / 1e18;
        uint256 lpFeeAmount = feeAmount - protocolFeeAmount;

        // LP fee recipient received their fees
        assertEq(assetTST.balanceOf(address(54321)), lpFeeAmount);

        // Protocol fee recipient received their fees
        assertEq(assetTST.balanceOf(address(8888)), protocolFeeAmount);
    }

    function test_fees_protocolFees_admin() public {
        {
            (address recipient, uint64 fee) = protocolFeeConfig.getProtocolFee(address(eulerSwap));
            assertEq(recipient, address(0));
            assertEq(fee, 0);
        }

        // Error cases

        vm.expectRevert(EulerSwapProtocolFeeConfig.Unauthorized.selector);
        protocolFeeConfig.setDefault(address(8888), 0.1e18);

        vm.prank(protocolFeeAdmin);
        vm.expectRevert(EulerSwapProtocolFeeConfig.InvalidProtocolFee.selector);
        protocolFeeConfig.setDefault(address(8888), 0.15000001e18);

        // Set a default

        vm.prank(protocolFeeAdmin);
        protocolFeeConfig.setDefault(address(8888), 0.08e18);

        {
            (address recipient, uint64 fee) = protocolFeeConfig.getProtocolFee(address(eulerSwap));
            assertEq(recipient, address(8888));
            assertEq(fee, 0.08e18);
        }

        // Override

        vm.prank(protocolFeeAdmin);
        protocolFeeConfig.setOverride(address(eulerSwap), address(9999), 0.07e18);

        {
            (address recipient, uint64 fee) = protocolFeeConfig.getProtocolFee(address(eulerSwap));
            assertEq(recipient, address(9999));
            assertEq(fee, 0.07e18);
        }

        // Fallback to default address

        vm.prank(protocolFeeAdmin);
        protocolFeeConfig.setOverride(address(eulerSwap), address(0), 0.07e18);

        {
            (address recipient, uint64 fee) = protocolFeeConfig.getProtocolFee(address(eulerSwap));
            assertEq(recipient, address(8888)); // default recipient
            assertEq(fee, 0.07e18); // overridden fee
        }

        // ...which is affected by changes to the default

        vm.prank(protocolFeeAdmin);
        protocolFeeConfig.setDefault(address(7777), 0.12e18);

        {
            (address recipient, uint64 fee) = protocolFeeConfig.getProtocolFee(address(eulerSwap));
            assertEq(recipient, address(7777)); // new default recipient
            assertEq(fee, 0.07e18); // same overridden fee
        }

        // Remove override

        vm.prank(protocolFeeAdmin);
        protocolFeeConfig.removeOverride(address(eulerSwap));

        {
            (address recipient, uint64 fee) = protocolFeeConfig.getProtocolFee(address(eulerSwap));
            assertEq(recipient, address(7777));
            assertEq(fee, 0.12e18);
        }
    }

    function test_fees_protocolFees_setAdmin() public {
        assertEq(protocolFeeConfig.admin(), protocolFeeAdmin);

        vm.expectRevert(EulerSwapProtocolFeeConfig.Unauthorized.selector);
        protocolFeeConfig.setDefault(address(8888), 0.1e18);

        vm.prank(protocolFeeAdmin);
        protocolFeeConfig.setAdmin(address(this));

        assertEq(protocolFeeConfig.admin(), address(this));

        protocolFeeConfig.setDefault(address(8888), 0.1e18);
    }

    function test_fuzzFeeRounding(uint256 amount, uint256 fee) public pure {
        // This test demonstrates why you don't need to round up fees required
        // when quoting an exact output swap. It's because the actual fee
        // subtracted during a deposit is rounded down.

        amount = bound(amount, 1, type(uint112).max);
        fee = bound(fee, 0, 1e18 - 1);

        // Exact out
        {
            uint256 quote = (amount * 1e18) / (1e18 - fee);
            uint256 feeAmount = quote * fee / 1e18;
            uint256 paid = quote - feeAmount;

            assertEq(paid, amount);
        }
    }
}
