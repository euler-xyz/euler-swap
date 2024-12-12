// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IMaglevBase {
    function configure() external;
    function setDebtLimit(uint112 _debtLimit0, uint112 _debtLimit1) external;
    function swap(uint256 _amount0Out, uint256 _amount1Out, address _to, bytes calldata _data) external;
    function quoteExactInput(address _tokenIn, address _tokenOut, uint256 _amountIn) external view returns (uint256);
    function quoteExactOutput(address _tokenIn, address _tokenOut, uint256 _amountOut)
        external
        view
        returns (uint256);

    function vault0() external view returns (address);
    function vault1() external view returns (address);
    function asset0() external view returns (address);
    function asset1() external view returns (address);
    function myAccount() external view returns (address);
    function reserve0() external view returns (uint112);
    function reserve1() external view returns (uint112);
    function initialReserve0() external view returns (uint112);
    function initialReserve1() external view returns (uint112);
}
