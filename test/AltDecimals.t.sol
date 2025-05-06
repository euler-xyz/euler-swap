// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract AltDecimals is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_alt_decimals_6_18_in() public {
        eulerSwap = createEulerSwap(50e6, 60e18, 0, 1e18, 1e6, 0.9e18, 0.9e18);
        skimAll(eulerSwap, true);

        uint256 amount = 1e6;
        uint256 q = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e18, 0.01e18);

        assetTST.mint(address(this), amount);
        assetTST.transfer(address(eulerSwap), amount);

        {
            uint256 qPlus = q + MAX_QUOTE_ERROR + 1;
            vm.expectRevert();
            eulerSwap.swap(0, qPlus, address(this), "");
        }

        eulerSwap.swap(0, q, address(this), "");
    }

    function test_alt_decimals_6_18_out() public {
        eulerSwap = createEulerSwap(50e6, 60e18, 0, 1e18, 1e6, 0.9e18, 0.9e18);
        skimAll(eulerSwap, true);

        uint256 amount = 1e18;
        uint256 q = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e6, 0.01e6);

        assetTST.mint(address(this), q);
        assetTST.transfer(address(eulerSwap), q);

        {
            uint256 amountPlus = amount + 0.0000001e18;
            vm.expectRevert();
            eulerSwap.swap(0, amountPlus, address(this), "");
        }

        eulerSwap.swap(0, amount, address(this), "");
    }

    function test_alt_decimals_18_6_in() public {
        eulerSwap = createEulerSwap(60e18, 50e6, 0, 1e6, 1e18, 0.9e18, 0.9e18);
        skimAll(eulerSwap, true);

        uint256 amount = 1e18;
        uint256 q = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e6, 0.01e6);

        assetTST.mint(address(this), amount);
        assetTST.transfer(address(eulerSwap), amount);

        {
            uint256 qPlus = q + MAX_QUOTE_ERROR + 1;
            vm.expectRevert();
            eulerSwap.swap(0, qPlus, address(this), "");
        }

        eulerSwap.swap(0, q, address(this), "");
    }

    function test_alt_decimals_18_6_out() public {
        eulerSwap = createEulerSwap(60e18, 50e6, 0, 1e6, 1e18, 0.9e18, 0.9e18);
        skimAll(eulerSwap, false);

        uint256 amount = 1e6;
        uint256 q = periphery.quoteExactOutput(address(eulerSwap), address(assetTST), address(assetTST2), amount);
        assertApproxEqAbs(q, 1e18, 0.01e18);

        assetTST.mint(address(this), q);
        assetTST.transfer(address(eulerSwap), q);

        {
            uint256 amountPlus = amount + 1;
            vm.expectRevert();
            eulerSwap.swap(0, amountPlus, address(this), "");
        }

        eulerSwap.swap(0, amount, address(this), "");
    }
}
