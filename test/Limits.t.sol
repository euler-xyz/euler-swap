// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {QuoteLib} from "../src/libraries/QuoteLib.sol";

contract LimitsTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.9e18, 0.9e18);
    }

    function test_basicLimits() public {
        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, type(uint112).max - 110e18); // max uint minus 110 (100 deposited by depositor, 10 by holder)
        assertEq(outLimit, 60e18);

        // Exact output

        uint256 quote = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 50e18);
        assertEq(quote, 75e18);

        quote = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 59.9999999e18);
        assertApproxEqAbs(quote, 3.6e27, 0.1e27);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        quote = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 60e18);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        quote = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 60.000001e18);

        // Exact input

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        quote = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), type(uint112).max);
    }

    function test_basicLimitsReverse() public view {
        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST2), address(assetTST));

        assertEq(outLimit, 60e18);
        assertEq(inLimit, type(uint112).max - 110e18);
    }

    function test_supplyCapExceeded() public {
        eTST.setCaps(uint16(2.72e2 << 6) | 18, 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, 0); // cap exceeded
        assertEq(outLimit, 60e18);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), 1);
    }

    function test_supplyCapExceededReverse() public {
        eTST2.setCaps(uint16(2.72e2 << 6) | 18, 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST2), address(assetTST));

        assertEq(inLimit, 0); // cap exceeded
        assertEq(outLimit, 60e18);
    }

    function test_supplyCapExtra() public {
        eTST.setCaps(uint16(2.72e2 << 6) | (18 + 2), 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, 162e18); // 272 - 110
        assertEq(outLimit, 60e18);

        uint256 quote =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), 161.9999e18);
        assertApproxEqAbs(quote, 56.9e18, 0.1e18);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), 162e18 + 1);
    }

    function test_utilisation() public {
        vm.prank(depositor);
        eTST2.withdraw(95e18, address(depositor), address(depositor));

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, type(uint112).max - 110e18);
        assertEq(outLimit, 15e18); // 110 - 95
    }

    function test_borrowCap() public {
        eTST2.setCaps(0, uint16(8.5e2 << 6) | 18);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, type(uint112).max - 110e18);
        assertEq(outLimit, 18.5e18); // 10 in balance, plus 8.5 borrow cap
    }

    function test_amountTooBig() public monotonicHolderNAV {
        vm.expectRevert(EulerSwap.AmountTooBig.selector);
        eulerSwap.swap(type(uint256).max, 0, address(this), "");

        vm.expectRevert(EulerSwap.AmountTooBig.selector);
        eulerSwap.swap(0, type(uint256).max, address(this), "");
    }

    function test_quoteWhenAboveCurve() public {
        // Donate 100 and 100 to the pool, raising the reserves above the curve
        assetTST.mint(depositor, 100e18);
        assetTST2.mint(depositor, 100e18);
        vm.prank(depositor);
        assetTST.transfer(address(eulerSwap), 10e18);
        vm.prank(depositor);
        assetTST2.transfer(address(eulerSwap), 10e18);
        eulerSwap.swap(0, 0, address(this), "");

        uint256 amount;

        // Exact output quotes: Costs nothing to perform this swap (in theory the quote could
        // be negative, but this is not supported by the interface)

        amount = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 1e18);
        assertEq(amount, 0);

        amount = periphery.quoteExactOutput(address(eulerSwap), address(assetTST2), address(assetTST), 1e18);
        assertEq(amount, 0);

        // Exact input quotes: The additional extractable value is provided as swap output, even
        // with tiny quotes such as 1 wei.

        amount = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), 1);
        assertApproxEqAbs(amount, 19.8e18, 0.1e18);

        amount = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), 1);
        assertApproxEqAbs(amount, 19.8e18, 0.1e18);
    }
}
