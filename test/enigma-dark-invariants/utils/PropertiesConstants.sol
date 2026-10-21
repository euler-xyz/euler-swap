// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract PropertiesConstants {
    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);
    uint256 constant INITIAL_BALANCE = 1000e30;

    // EulerSwap constants
    uint256 constant MAX_LEVERAGE = 10;
    uint256 constant MIN_LEVERAGE = 1;

    // EVault constants
    uint16 constant MAX_LIQUIDATION_DISCOUNT = 0.2e4;
    uint16 constant LIQUIDATION_LTV = 0.9e4;
    uint16 constant BORROW_LTV = 0.9e4;
}
