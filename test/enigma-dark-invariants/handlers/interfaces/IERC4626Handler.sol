// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC4626Handler {
    function withdraw(uint256 assets, uint8 i) external;
    function redeem(uint256 shares, uint8 i) external;
}
