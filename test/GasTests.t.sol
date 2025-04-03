// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IEVault, IEulerSwap, EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract EulerSwapGas is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();

        eulerSwap = createEulerSwap(60e18, 60e18, 0, 1e18, 1e18, 0.9e18, 0.9e18);
        eulerSwap.activate();
    }

    function test_gas_smallSwap() public {
        {
            uint256 amountIn = 1e18;
            uint256 amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);

            eulerSwap.swap(0, amountOut, address(this), "");
            vm.snapshotGasLastCall("small swap, fresh");
        }

        {
            uint256 amountIn = 1e18;
            uint256 amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);

            eulerSwap.swap(0, amountOut, address(this), "");
            vm.snapshotGasLastCall("small swap, existing");
        }

        {
            uint256 amountIn = 5e18;
            uint256 amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);

            assetTST2.mint(address(this), amountIn);
            assetTST2.transfer(address(eulerSwap), amountIn);

            eulerSwap.swap(amountOut, 0, address(this), "");
            vm.snapshotGasLastCall("small swap, cross 0 point");
        }
    }

    function test_gas_bigSwap() public {
        {
            uint256 amountIn = 30e18;
            uint256 amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST), address(assetTST2), amountIn);

            assetTST.mint(address(this), amountIn);
            assetTST.transfer(address(eulerSwap), amountIn);

            eulerSwap.swap(0, amountOut, address(this), "");
            vm.snapshotGasLastCall("big swap, fresh");
        }

        {
            uint256 amountIn = 60e18;
            uint256 amountOut = periphery.quoteExactInput(address(eulerSwap), address(assetTST2), address(assetTST), amountIn);

            assetTST2.mint(address(this), amountIn);
            assetTST2.transfer(address(eulerSwap), amountIn);

            eulerSwap.swap(amountOut, 0, address(this), "");
            vm.snapshotGasLastCall("big swap, cross 0 point");
        }
    }
}
