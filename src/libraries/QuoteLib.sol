// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap} from "../interfaces/IEulerSwap.sol";
import "../interfaces/IEulerSwapHookTarget.sol";
import {CtxLib} from "./CtxLib.sol";
import {CurveLib} from "./CurveLib.sol";
import {SwapLib} from "./SwapLib.sol";

library QuoteLib {
    error HookError();
    error UnsupportedPair();
    error OperatorNotInstalled();
    error SwapLimitExceeded();
    error SwapRejected();
    error Expired();

    function getFee(IEulerSwap.DynamicParams memory dParams, bool asset0IsInput) internal returns (uint64 fee) {
        fee = type(uint64).max;

        if ((dParams.swapHookedOperations & EULER_SWAP_HOOK_GET_FEE) != 0) {
            CtxLib.State storage s = CtxLib.getState();

            (bool success, bytes memory data) = dParams.swapHook.call(
                abi.encodeCall(IEulerSwapHookTarget.getFee, (asset0IsInput, s.reserve0, s.reserve1, false))
            );
            require(success && data.length >= 32, SwapLib.HookError(EULER_SWAP_HOOK_GET_FEE, data));
            fee = abi.decode(data, (uint64));
        }

        if (fee == type(uint64).max) fee = asset0IsInput ? dParams.fee0 : dParams.fee1;
    }

    function getFeeReadOnly(IEulerSwap.DynamicParams memory dParams, bool asset0IsInput)
        internal
        view
        returns (uint64 fee)
    {
        fee = type(uint64).max;

        if ((dParams.swapHookedOperations & EULER_SWAP_HOOK_GET_FEE) != 0) {
            CtxLib.State storage s = CtxLib.getState();

            (bool success, bytes memory data) = dParams.swapHook.staticcall(
                abi.encodeCall(IEulerSwapHookTarget.getFee, (asset0IsInput, s.reserve0, s.reserve1, true))
            );
            require(success && data.length >= 32, SwapLib.HookError(EULER_SWAP_HOOK_GET_FEE, data));
            fee = abi.decode(data, (uint64));
        }

        if (fee == type(uint64).max) fee = asset0IsInput ? dParams.fee0 : dParams.fee1;
    }

    /// @dev Computes the quote for a swap by applying fees and validating state conditions
    /// @param evc EVC instance
    /// @param sParams Static params
    /// @param dParams Dynamic params
    /// @param asset0IsInput Swap direction
    /// @param amount The amount to quote (input amount if exactIn=true, output amount if exactIn=false)
    /// @param exactIn True if quoting for exact input amount, false if quoting for exact output amount
    /// @return The quoted amount (output amount if exactIn=true, input amount if exactIn=false)
    /// @dev Validates:
    ///      - EulerSwap operator is installed
    ///      - Token pair is supported
    ///      - Sufficient reserves exist
    ///      - Sufficient cash is available
    function computeQuote(
        address evc,
        IEulerSwap.StaticParams memory sParams,
        IEulerSwap.DynamicParams memory dParams,
        bool asset0IsInput,
        uint256 amount,
        bool exactIn
    ) internal view returns (uint256) {
        if (amount == 0) return 0;

        require(amount <= type(uint112).max, SwapLimitExceeded());

        require(IEVC(evc).isAccountOperatorAuthorized(sParams.eulerAccount, address(this)), OperatorNotInstalled());
        require(dParams.expiration == 0 || dParams.expiration > block.timestamp, Expired());

        uint256 fee = getFeeReadOnly(dParams, asset0IsInput);
        require(fee < 1e18, SwapRejected());

        (uint256 inLimit, uint256 outLimit) = calcLimits(sParams, dParams, asset0IsInput, fee);

        // exactIn: decrease effective amountIn
        if (exactIn) amount = amount - (amount * fee / 1e18);

        uint256 quote = findCurvePoint(dParams, amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(amount <= inLimit && quote <= outLimit, SwapLimitExceeded());
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(amount <= outLimit && quote <= inLimit, SwapLimitExceeded());

            // exactOut: inflate required amountIn
            quote = (quote * 1e18) / (1e18 - fee);
        }

        return quote;
    }

    /// @notice Calculates the maximum input and output amounts for a swap based on protocol constraints
    /// @dev Determines limits by checking multiple factors:
    ///      1. Supply caps and existing debt for the input token
    ///      2. Available reserves in the EulerSwap for the output token
    ///      3. Available cash and borrow caps for the output token
    ///      4. Account balances in the respective vaults
    /// @param sParams Static params
    /// @param dParams Dynamic params
    /// @param asset0IsInput Boolean indicating whether asset0 (true) or asset1 (false) is the input token
    /// @param fee Amount of fee required for this swap
    /// @return uint256 Maximum amount of input token that can be deposited
    /// @return uint256 Maximum amount of output token that can be withdrawn
    function calcLimits(
        IEulerSwap.StaticParams memory sParams,
        IEulerSwap.DynamicParams memory dParams,
        bool asset0IsInput,
        uint256 fee
    ) internal view returns (uint256, uint256) {
        CtxLib.State storage s = CtxLib.getState();

        uint256 inLimit = type(uint112).max;
        uint256 outLimit = type(uint112).max;

        address eulerAccount = sParams.eulerAccount;

        // Supply caps on input
        {
            IEVault supplyVault = IEVault(asset0IsInput ? sParams.supplyVault0 : sParams.supplyVault1);
            IEVault borrowVault = IEVault(asset0IsInput ? sParams.borrowVault0 : sParams.borrowVault1);
            uint256 maxDeposit = supplyVault.maxDeposit(eulerAccount);
            if (address(borrowVault) != address(0)) maxDeposit += borrowVault.debtOf(eulerAccount);
            if (maxDeposit < inLimit) inLimit = maxDeposit;
        }

        // Remaining reserves of output
        {
            uint112 reserveLimit =
                asset0IsInput ? (s.reserve1 - dParams.minReserve1) : (s.reserve0 - dParams.minReserve0);
            if (reserveLimit < outLimit) outLimit = reserveLimit;
        }

        // Remaining cash and borrow caps in output
        {
            IEVault supplyVault = IEVault(asset0IsInput ? sParams.supplyVault1 : sParams.supplyVault0);
            IEVault borrowVault = IEVault(asset0IsInput ? sParams.borrowVault1 : sParams.borrowVault0);
            uint256 supplyBalance = supplyVault.convertToAssets(supplyVault.balanceOf(eulerAccount));

            {
                uint256 supplyCash = supplyVault.cash();
                if (supplyBalance > supplyCash || supplyVault == borrowVault) {
                    // Cash in supplyVault is limiting factor
                    if (supplyCash < outLimit) outLimit = supplyCash;
                } else {
                    // Sufficient cash to cover full withdrawal, so limiting factor is cash in borrowVault
                    uint256 cashLimit = supplyBalance;
                    if (address(borrowVault) != address(0)) cashLimit += borrowVault.cash();
                    if (cashLimit < outLimit) outLimit = cashLimit;
                }
            }

            if (address(borrowVault) != address(0)) {
                (, uint16 borrowCapEncoded) = borrowVault.caps();
                uint256 borrowCap = decodeCap(uint256(borrowCapEncoded));
                if (borrowCap != type(uint256).max) {
                    uint256 totalBorrows = borrowVault.totalBorrows();
                    uint256 maxWithdraw = supplyBalance + (totalBorrows > borrowCap ? 0 : borrowCap - totalBorrows);
                    if (maxWithdraw < outLimit) outLimit = maxWithdraw;
                }
            }
        }

        {
            uint256 inLimit2 = findCurvePoint(dParams, outLimit, false, asset0IsInput);

            if (inLimit2 <= type(uint112).max) {
                if (inLimit2 < inLimit) inLimit = inLimit2 * 1e18 / (1e18 - fee);
            } else {
                uint256 outLimit2 = findCurvePoint(dParams, inLimit * (1e18 - fee) / 1e18, true, asset0IsInput);
                if (outLimit2 < outLimit) {
                    outLimit = outLimit2;
                    inLimit2 = findCurvePoint(dParams, outLimit, false, asset0IsInput) * 1e18 / (1e18 - fee);
                    if (inLimit2 < inLimit) inLimit = inLimit2;
                }
            }
        }

        return (inLimit, outLimit);
    }

    /// @notice Decodes a compact-format cap value to its actual numerical value
    /// @dev The cap uses a compact-format where:
    ///      - If amountCap == 0, there's no cap (returns max uint256)
    ///      - Otherwise, the lower 6 bits represent the exponent (10^exp)
    ///      - The upper bits (>> 6) represent the mantissa
    ///      - The formula is: (10^exponent * mantissa) / 100
    /// @param amountCap The compact-format cap value to decode
    /// @return The actual numerical cap value (type(uint256).max if uncapped)
    /// @custom:security Uses unchecked math for gas optimization as calculations cannot overflow:
    ///                  maximum possible value 10^(2^6-1) * (2^10-1) ≈ 1.023e+66 < 2^256
    function decodeCap(uint256 amountCap) internal pure returns (uint256) {
        if (amountCap == 0) return type(uint256).max;

        unchecked {
            // Cannot overflow because this is less than 2**256:
            //   10**(2**6 - 1) * (2**10 - 1) = 1.023e+66
            return 10 ** (amountCap & 63) * (amountCap >> 6) / 100;
        }
    }

    /// @notice Verifies that the given tokens are supported by the EulerSwap pool and determines swap direction
    /// @dev Returns a boolean indicating whether the input token is asset0 (true) or asset1 (false)
    /// @param sParams Static params
    /// @param tokenIn The input token address for the swap
    /// @param tokenOut The output token address for the swap
    /// @return asset0IsInput True if tokenIn is asset0 and tokenOut is asset1, false if reversed
    /// @custom:error UnsupportedPair Thrown if the token pair is not supported by the EulerSwap pool
    function checkTokens(IEulerSwap.StaticParams memory sParams, address tokenIn, address tokenOut)
        internal
        view
        returns (bool asset0IsInput)
    {
        address asset0 = IEVault(sParams.supplyVault0).asset();
        address asset1 = IEVault(sParams.supplyVault1).asset();

        if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
        else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
        else revert UnsupportedPair();
    }

    function findCurvePoint(IEulerSwap.DynamicParams memory dParams, uint256 amount, bool exactIn, bool asset0IsInput)
        internal
        view
        returns (uint256 output)
    {
        CtxLib.State storage s = CtxLib.getState();
        uint112 reserve0 = s.reserve0;
        uint112 reserve1 = s.reserve1;

        uint256 px = dParams.priceX;
        uint256 py = dParams.priceY;
        uint256 x0 = dParams.equilibriumReserve0;
        uint256 y0 = dParams.equilibriumReserve1;
        uint256 cx = dParams.concentrationX;
        uint256 cy = dParams.concentrationY;

        uint256 xNew;
        uint256 yNew;

        if (exactIn) {
            // exact in
            if (asset0IsInput) {
                // swap X in and Y out
                xNew = reserve0 + amount;
                if (xNew <= x0) {
                    // remain on f()
                    yNew = CurveLib.f(xNew, px, py, x0, y0, cx);
                } else {
                    // move to g()
                    yNew = CurveLib.fInverse(xNew, py, px, y0, x0, cy);
                }
                output = reserve1 > yNew ? reserve1 - yNew : 0;
            } else {
                // swap Y in and X out
                yNew = reserve1 + amount;
                if (yNew <= y0) {
                    // remain on g()
                    xNew = CurveLib.f(yNew, py, px, y0, x0, cy);
                } else {
                    // move to f()
                    xNew = CurveLib.fInverse(yNew, px, py, x0, y0, cx);
                }
                output = reserve0 > xNew ? reserve0 - xNew : 0;
            }
        } else {
            // exact out
            if (asset0IsInput) {
                // swap Y out and X in
                if (reserve1 <= amount) return type(uint256).max;
                yNew = reserve1 - amount;
                if (yNew <= y0) {
                    // remain on g()
                    xNew = CurveLib.f(yNew, py, px, y0, x0, cy);
                } else {
                    // move to f()
                    xNew = CurveLib.fInverse(yNew, px, py, x0, y0, cx);
                }
                output = xNew > reserve0 ? xNew - reserve0 : 0;
            } else {
                // swap X out and Y in
                if (reserve0 <= amount) return type(uint256).max;
                xNew = reserve0 - amount;
                if (xNew <= x0) {
                    // remain on f()
                    yNew = CurveLib.f(xNew, px, py, x0, y0, cx);
                } else {
                    // move to g()
                    yNew = CurveLib.fInverse(xNew, py, px, y0, x0, cy);
                }
                output = yNew > reserve1 ? yNew - reserve1 : 0;
            }
        }
    }
}
