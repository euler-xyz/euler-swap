// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IMaglevBase} from "./IMaglevBase.sol";

interface IMaglevEulerSwap is IMaglevBase {
    function px() external view returns (uint256);
    function py() external view returns (uint256);
    function cx() external view returns (uint256);
    function cy() external view returns (uint256);
    function fee() external view returns (uint256);
}
