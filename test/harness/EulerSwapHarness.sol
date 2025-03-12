// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EulerSwap, IEulerSwap} from "../../src/EulerSwap.sol";

contract EulerSwapHarness is EulerSwap {
    constructor(IEulerSwap.Params memory params, IEulerSwap.CurveParams memory curveParams)
        EulerSwap(params, curveParams)
    {}

    /// @notice Exposes the internal f() function as a public function for testing
    function exposedF(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)
        external
        pure
        returns (uint256)
    {
        return f(x, px, py, x0, y0, c);
    }
}
