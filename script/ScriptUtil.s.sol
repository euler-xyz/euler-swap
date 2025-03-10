// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

contract ScriptUtil is Script {
    function _getJsonFile(string memory _jsonFile) internal view returns (string memory) {
        return vm.readFile(_getJsonFilePath(_jsonFile));
    }

    function _getJsonFilePath(string memory _jsonFile) private view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/script/json/", _jsonFile);
    }
}
