// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";
import {IGovernance} from "evk/EVault/IEVault.sol";

contract NoPermit2 is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        vm.mockCall(address(eTST), abi.encodeWithSelector(IGovernance.permit2Address.selector), abi.encode(address(0)));

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.4e18, 0.85e18);

        vm.clearMockedCalls();
    }

    function test_noPermit2Installed() public {
        assertEq(assetTST.allowance(address(eulerSwap), address(eTST)), type(uint256).max);
        assertEq(assetTST.allowance(address(eulerSwap), eTST.permit2Address()), 0);

        uint256 amountIn = 1e18;
        uint256 amountOut =
            periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);
        assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18);

        assetTST.mint(address(this), amountIn);

        assetTST.transfer(address(eulerSwap), amountIn);
        eulerSwap.swap(0, amountOut, address(this), "");

        assertEq(assetTST2.balanceOf(address(this)), amountOut);
    }
}
