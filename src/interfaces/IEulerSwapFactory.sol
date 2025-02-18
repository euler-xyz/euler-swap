// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IEulerSwapFactory {
    struct DeployParams {
        address vault0;
        address vault1;
        address swapAccount;
        uint256 fee;
        uint256 priceX;
        uint256 priceY;
        uint256 concentrationX;
        uint256 concentrationY;
        uint112 debtLimit0;
        uint112 debtLimit1;
    }

    function deployPool(DeployParams memory params) external returns (address);

    function allPools(uint256 index) external view returns (address);
    function getPool(bytes32 poolKey) external view returns (address);
    function allPoolsLength() external view returns (uint256);
    function getAllPoolsListSlice(uint256 start, uint256 end) external view returns (address[] memory);
}
