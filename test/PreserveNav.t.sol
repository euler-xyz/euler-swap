// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, EulerSwap, TestERC20} from "./EulerSwapTestBase.t.sol";

contract PreserveNav is EulerSwapTestBase {
    EulerSwap public eulerSwap;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_preserveNav(
        uint256 cx,
        uint256 cy,
        uint256 fee,
        bool preSkimDir,
        bool dir1,
        uint256 amount1,
        bool dir2,
        uint256 amount2
    ) public {
        cx = bound(cx, 0e18, 1e18);
        cy = bound(cx, 0e18, 1e18);
        fee = bound(fee, 0, 0.2e18);
        amount1 = bound(amount1, 0.00001e18, 25e18);
        amount2 = bound(amount2, 0.00001e18, 25e18);

        if (fee < 0.1e18) fee = 0; // half of the time use fee 0

        else fee -= 0.1e18;

        eulerSwap = createEulerSwap(60e18, 60e18, uint64(fee), 1e18, 1e18, uint64(cx), uint64(cy));

        skimAll(eulerSwap, preSkimDir);
        int256 nav1 = getHolderNAV();

        {
            TestERC20 t1;
            TestERC20 t2;
            if (dir1) (t1, t2) = (assetTST, assetTST2);
            else (t1, t2) = (assetTST2, assetTST);

            uint256 q = periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amount1);
            {
                uint256 qRev = periphery.quoteExactOutput(address(eulerSwap), address(t1), address(t2), q);
                assertApproxEqAbs(amount1, qRev, (MAX_QUOTE_ERROR + 1) * 2);
            }

            t1.mint(address(this), amount1);
            t1.transfer(address(eulerSwap), amount1);

            {
                uint256 qPlus = q + MAX_QUOTE_ERROR + 1;
                vm.expectRevert();
                if (dir1) eulerSwap.swap(0, qPlus, address(this), "");
                else eulerSwap.swap(qPlus, 0, address(this), "");
            }

            if (dir1) eulerSwap.swap(0, q, address(this), "");
            else eulerSwap.swap(q, 0, address(this), "");
        }

        assertGe(getHolderNAV(), nav1);

        {
            TestERC20 t1;
            TestERC20 t2;
            if (dir2) (t1, t2) = (assetTST, assetTST2);
            else (t1, t2) = (assetTST2, assetTST);

            uint256 q = periphery.quoteExactInput(address(eulerSwap), address(t1), address(t2), amount2);
            {
                uint256 qRev = periphery.quoteExactOutput(address(eulerSwap), address(t1), address(t2), q);
                assertApproxEqAbs(amount2, qRev, (MAX_QUOTE_ERROR + 1) * 2);
            }

            t1.mint(address(this), amount2);
            t1.transfer(address(eulerSwap), amount2);

            {
                uint256 qPlus = q + MAX_QUOTE_ERROR + 1;
                vm.expectRevert();
                if (dir2) eulerSwap.swap(0, qPlus, address(this), "");
                else eulerSwap.swap(qPlus, 0, address(this), "");
            }

            if (dir2) eulerSwap.swap(0, q, address(this), "");
            else eulerSwap.swap(q, 0, address(this), "");
        }

        assertGe(getHolderNAV(), nav1);
    }
}
