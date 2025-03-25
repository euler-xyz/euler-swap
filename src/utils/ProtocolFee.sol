// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";

abstract contract ProtocolFee is Owned {
    uint256 public protocolFee; // percentage, i.e. 0.05e18 5%

    uint256 public asset0Accrued;
    uint256 public asset1Accrued;

    constructor() Owned(msg.sender) {}

    function _accrueAsset0(uint256 amount) internal {
        asset0Accrued += amount;
    }

    function _accrueAsset1(uint256 amount) internal {
        asset1Accrued += amount;
    }

    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        protocolFee = _protocolFee;
    }

    function collectProtocolFee(address asset, address recipient) external onlyOwner {
        // collect protocol fee
        uint256 amount = asset == _asset0() ? asset0Accrued : asset1Accrued;
        IERC20(asset).transfer(recipient, amount);
        if (asset == _asset0()) {
            asset0Accrued = 0;
        } else {
            asset1Accrued = 0;
        }
    }

    function _asset0() internal view virtual returns (address);
    function _asset1() internal view virtual returns (address);
}
