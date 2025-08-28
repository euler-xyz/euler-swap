// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IPerspective} from "../../src/interfaces/IPerspective.sol";

import "forge-std/Test.sol";

contract PerspectiveMock is IPerspective {
    mapping(address => bool) blacklist;

    function setBlacklist(address vault, bool bl) external {
        blacklist[vault] = bl;
    }

    function isVerified(address vault) external view returns (bool) {
        if (blacklist[vault]) return false;
        return true;
    }
}
