// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, EulerSwapPeriphery, IEulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {QuoteLib} from "../src/libraries/QuoteLib.sol";

contract LimitsTest is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0.02e18, 1e18, 1e18, 0.9e18, 0.9e18);
    }

    modifier isSwappable() {
        _;
        verifyInLimitSwappable(eulerSwap, assetTST, assetTST2);
        verifyInLimitSwappable(eulerSwap, assetTST2, assetTST);
        verifyOutLimitSwappable(eulerSwap, assetTST, assetTST2);
        verifyOutLimitSwappable(eulerSwap, assetTST2, assetTST);
    }

    function test_basicLimits() public isSwappable {
        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertTrue(inLimit >= type(uint112).max / 2); // big value that maps to output amount
        assertApproxEqAbs(outLimit, 60e18, 0.00001e18);

        // Exact output

        uint256 quote = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 50e18);
        assertApproxEqAbs(quote, 76.5e18, 0.1e18);

        quote = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), outLimit - 1);
        assertLt(quote, inLimit);
        assertGt(quote, inLimit * 0.99e18 / 1e18);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        quote =
            periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), outLimit + 0.0001e18);

        // Exact input

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        quote = periphery.quoteExactInput(
            address(eulerSwap), address(assetTST), address(assetTST2), inLimit * 1.01e18 / 1e18
        );
    }

    function test_basicLimitsReverse() public isSwappable {
        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST2), address(assetTST));

        assertTrue(inLimit >= type(uint112).max / 2); // big value that maps to output amount
        assertLt(outLimit, 60e18);
        assertApproxEqAbs(outLimit, 60e18, 0.00001e18);
    }

    function test_supplyCapExceeded() public isSwappable {
        eTST.setCaps(uint16(2.72e2 << 6) | 18, 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertEq(inLimit, 0); // cap exceeded
        assertEq(outLimit, 0);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), 1);
    }

    function test_supplyCapExceededReverse() public isSwappable {
        eTST2.setCaps(uint16(2.72e2 << 6) | 18, 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST2), address(assetTST));

        assertEq(inLimit, 0); // cap exceeded
        assertEq(outLimit, 0);
    }

    function test_supplyCapExtra() public isSwappable {
        eTST.setCaps(uint16(2.72e2 << 6) | (18 + 2), 0);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertApproxEqAbs(inLimit, 162e18, 0.00001e18);
        assertApproxEqAbs(outLimit, 56.9e18, 0.1e18);

        uint256 quote =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), inLimit - 0.1e18);
        assertApproxEqAbs(quote, 56.9e18, 0.1e18);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), inLimit + 0.1e18);
    }

    function test_utilisation() public isSwappable {
        vm.prank(depositor);
        eTST2.withdraw(95e18, address(depositor), address(depositor));

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertApproxEqAbs(inLimit, 15.81e18, 0.01e18);
        assertEq(outLimit, 15e18 - 1); // 110 - 95
    }

    function test_borrowCap() public isSwappable {
        eTST2.setCaps(0, uint16(8.5e2 << 6) | 18);

        (uint256 inLimit, uint256 outLimit) =
            periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));

        assertApproxEqAbs(inLimit, 19.71e18, 0.01e18);
        assertEq(outLimit, 18.5e18 - 1); // 10 in balance, plus 8.5 borrow cap
    }

    function test_amountTooBig() public isSwappable {
        vm.expectRevert(EulerSwap.AmountTooBig.selector);
        eulerSwap.swap(type(uint256).max, 0, address(this), "");

        vm.expectRevert(EulerSwap.AmountTooBig.selector);
        eulerSwap.swap(0, type(uint256).max, address(this), "");
    }

    function test_quoteWhenAboveCurve() public isSwappable {
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
        assertApproxEqAbs(amount, 19.4e18, 0.1e18);

        amount = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), 1);
        assertApproxEqAbs(amount, 19.4e18, 0.1e18);
    }

    function test_disabledFee0() public isSwappable {
        PoolConfig memory pc = getPoolConfig(eulerSwap);
        pc.dParams.fee0 = 1e18;
        reconfigurePool(eulerSwap, pc);

        {
            (uint256 inLimit, uint256 outLimit) =
                periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
            assertEq(inLimit, 0);
            assertEq(outLimit, 0);
        }

        {
            (, uint256 outLimit) = periphery.getLimits(address(eulerSwap), address(assetTST2), address(assetTST));
            assertLt(outLimit, 60e18);
            assertApproxEqAbs(outLimit, 60e18, 0.00001e18);
        }
    }

    function test_disabledFee1() public isSwappable {
        PoolConfig memory pc = getPoolConfig(eulerSwap);
        pc.dParams.fee1 = 1e18;
        reconfigurePool(eulerSwap, pc);

        {
            (, uint256 outLimit) = periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
            assertLt(outLimit, 60e18);
            assertApproxEqAbs(outLimit, 60e18, 0.00001e18);
        }

        {
            (uint256 inLimit, uint256 outLimit) =
                periphery.getLimits(address(eulerSwap), address(assetTST2), address(assetTST));
            assertEq(inLimit, 0);
            assertEq(outLimit, 0);
        }
    }

    function test_quoteMinReserves() public isSwappable {
        PoolConfig memory pc = getPoolConfig(eulerSwap);
        pc.dParams.minReserve0 = 40e18;
        pc.dParams.minReserve1 = 50e18;
        reconfigurePool(eulerSwap, pc);

        {
            (, uint256 outLimit) = periphery.getLimits(address(eulerSwap), address(assetTST), address(assetTST2));
            assertEq(outLimit, 10e18 - 1);
        }

        {
            (, uint256 outLimit) = periphery.getLimits(address(eulerSwap), address(assetTST2), address(assetTST));
            assertEq(outLimit, 20e18 - 1);
        }

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 10e18 + 1);

        periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), 10e18);

        vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
        periphery.quoteExactOutput(address(eulerSwap), address(assetTST2), address(assetTST), 20e18 + 1);

        periphery.quoteExactOutput(address(eulerSwap), address(assetTST2), address(assetTST), 20e18);
    }

    function test_getLimitsTightness(uint256 cx, uint256 cy, uint256 price, uint256 fee, bool dir) public {
        cx = bound(cx, 0e18, 1e18);
        cy = bound(cy, 0e18, 1e18);
        price = bound(price, 1, 1e24);
        fee = bound(fee, 0, 0.2e18);

        {
            uint256 px = price;
            uint256 py = 1e18;
            oracle.setPrice(address(eTST), unitOfAccount, price);
            oracle.setPrice(address(assetTST), unitOfAccount, price);

            eulerSwap = createEulerSwap(60e18, 60e18, 0, uint80(px), uint80(py), uint64(cx), uint64(cy));
        }

        TestERC20 t1;
        TestERC20 t2;
        if (dir) (t1, t2) = (assetTST, assetTST2);
        else (t1, t2) = (assetTST2, assetTST);

        verifyInLimitSwappable(eulerSwap, t1, t2);
        verifyInLimitSwappable(eulerSwap, t2, t1);
        verifyOutLimitSwappable(eulerSwap, t1, t2);
        verifyOutLimitSwappable(eulerSwap, t2, t1);
    }
}
