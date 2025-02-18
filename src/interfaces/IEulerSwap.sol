// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IEulerSwap {
    struct Params {
        address vault0;
        address vault1;
        address swapAccount;
        uint112 debtLimit0;
        uint112 debtLimit1;
        uint256 fee;
    }

    struct CurveParams {
        uint256 priceX;
        uint256 priceY;
        uint256 concentrationX;
        uint256 concentrationY;
    }

    /// @notice Optimistically sends the requested amounts of tokens to the `to`
    /// address, invokes `uniswapV2Call` callback on `to` (if `data` was provided),
    /// and then verifies that a sufficient amount of tokens were transferred to
    /// satisfy the swapping curve invariant.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    /// @notice Approves the vaults to access the EulerSwap instance's tokens, and enables
    /// vaults as collateral. Can be invoked by anybody, and is harmless if invoked again.
    /// Calling this function is optional: EulerSwap can be activated on the first swap.
    function activate() external;

    /// @notice Function that defines the shape of the swapping curve. Returns true iff
    /// the specified reserve amounts would be acceptable (ie it is above and to-the-right
    /// of the swapping curve).
    function verify(uint256 newReserve0, uint256 newReserve1) external view returns (bool);

    // EulerSwap Accessors

    function curve() external view returns (bytes32);
    function vault0() external view returns (address);
    function vault1() external view returns (address);
    function asset0() external view returns (address);
    function asset1() external view returns (address);
    function swapAccount() external view returns (address);
    function initialReserve0() external view returns (uint112);
    function initialReserve1() external view returns (uint112);
    function feeMultiplier() external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 status);

    // Curve Accessors

    function priceX() external view returns (uint256);
    function priceY() external view returns (uint256);
    function concentrationX() external view returns (uint256);
    function concentrationY() external view returns (uint256);
}
