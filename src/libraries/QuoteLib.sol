// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap} from "../interfaces/IEulerSwap.sol";
import {CtxLib} from "./CtxLib.sol";
import {CurveLib} from "./CurveLib.sol";

library QuoteLib {
    error UnsupportedPair();
    error OperatorNotInstalled();
    error SwapLimitExceeded();

    /// @dev Computes the quote for a swap by applying fees and validating state conditions
    /// @param evc EVC instance
    /// @param p The EulerSwap params
    /// @param asset0IsInput Swap direction
    /// @param amount The amount to quote (input amount if exactIn=true, output amount if exactIn=false)
    /// @param exactIn True if quoting for exact input amount, false if quoting for exact output amount
    /// @return The quoted amount (output amount if exactIn=true, input amount if exactIn=false)
    /// @dev Validates:
    ///      - EulerSwap operator is installed
    ///      - Token pair is supported
    ///      - Sufficient reserves exist
    ///      - Sufficient cash is available
    function computeQuote(address evc, IEulerSwap.Params memory p, bool asset0IsInput, uint256 amount, bool exactIn)
        internal
        view
        returns (uint256)
    {
        if (amount == 0) return 0;

        require(IEVC(evc).isAccountOperatorAuthorized(p.eulerAccount, address(this)), OperatorNotInstalled());
        require(amount <= type(uint112).max, SwapLimitExceeded());

        uint256 fee = p.fee;

        // exactIn: decrease effective amountIn
        if (exactIn) amount = amount - (amount * fee / 1e18);

        (uint256 inLimit, uint256 outLimit) = calcLimits(p, asset0IsInput);

        uint256 quote = findCurvePoint(p, amount, exactIn, asset0IsInput);

        if (exactIn) {
            // if `exactIn`, `quote` is the amount of assets to buy from the AMM
            require(amount <= inLimit && quote <= outLimit, SwapLimitExceeded());
        } else {
            // if `!exactIn`, `amount` is the amount of assets to buy from the AMM
            require(amount <= outLimit && quote <= inLimit, SwapLimitExceeded());
        }

        // exactOut: inflate required amountIn
        if (!exactIn) quote = (quote * 1e18) / (1e18 - fee);

        return quote;
    }

    /// @notice Calculates the maximum input and output amounts for a swap based on protocol constraints
    /// @dev Determines limits by checking multiple factors:
    ///      1. Supply caps and existing debt for the input token
    ///      2. Available reserves in the EulerSwap for the output token
    ///      3. Available cash and borrow caps for the output token
    ///      4. Account balances in the respective vaults
    /// @param p The EulerSwap params
    /// @param asset0IsInput Boolean indicating whether asset0 (true) or asset1 (false) is the input token
    /// @return uint256 Maximum amount of input token that can be deposited
    /// @return uint256 Maximum amount of output token that can be withdrawn
    function calcLimits(IEulerSwap.Params memory p, bool asset0IsInput) internal view returns (uint256, uint256) {
        CtxLib.Storage storage s = CtxLib.getStorage();

        uint256 inLimit = type(uint112).max;
        uint256 outLimit = type(uint112).max;

        address eulerAccount = p.eulerAccount;
        (IEVault vault0, IEVault vault1) = (IEVault(p.vault0), IEVault(p.vault1));
        // Supply caps on input
        {
            IEVault vault = (asset0IsInput ? vault0 : vault1);
            uint256 maxDeposit = vault.debtOf(eulerAccount) + vault.maxDeposit(eulerAccount);
            if (maxDeposit < inLimit) inLimit = maxDeposit;
        }

        // Remaining reserves of output
        {
            uint112 reserveLimit = asset0IsInput ? s.reserve1 : s.reserve0;
            if (reserveLimit < outLimit) outLimit = reserveLimit;
        }

        // Remaining cash and borrow caps in output
        {
            IEVault vault = (asset0IsInput ? vault1 : vault0);

            uint256 cash = vault.cash();
            if (cash < outLimit) outLimit = cash;

            (, uint16 borrowCap) = vault.caps();
            uint256 maxWithdraw = decodeCap(uint256(borrowCap));
            maxWithdraw = vault.totalBorrows() > maxWithdraw ? 0 : maxWithdraw - vault.totalBorrows();
            if (maxWithdraw < outLimit) {
                maxWithdraw += vault.convertToAssets(vault.balanceOf(eulerAccount));
                if (maxWithdraw < outLimit) outLimit = maxWithdraw;
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
    /// @param p The EulerSwap params
    /// @param tokenIn The input token address for the swap
    /// @param tokenOut The output token address for the swap
    /// @return asset0IsInput True if tokenIn is asset0 and tokenOut is asset1, false if reversed
    /// @custom:error UnsupportedPair Thrown if the token pair is not supported by the EulerSwap pool
    function checkTokens(IEulerSwap.Params memory p, address tokenIn, address tokenOut)
        internal
        view
        returns (bool asset0IsInput)
    {
        address asset0 = IEVault(p.vault0).asset();
        address asset1 = IEVault(p.vault1).asset();

        if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
        else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
        else revert UnsupportedPair();
    }

    function findCurvePoint(IEulerSwap.Params memory p, uint256 amount, bool exactIn, bool asset0IsInput)
        internal
        view
        returns (uint256 output)
    {
        CtxLib.Storage storage s = CtxLib.getStorage();

        uint256 px = p.priceX;
        uint256 py = p.priceY;
        uint256 x0 = p.equilibriumReserve0;
        uint256 y0 = p.equilibriumReserve1;
        uint256 cx = p.concentrationX;
        uint256 cy = p.concentrationY;
        uint112 reserve0 = s.reserve0;
        uint112 reserve1 = s.reserve1;

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
                require(reserve1 > amount, SwapLimitExceeded());
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
                require(reserve0 > amount, SwapLimitExceeded());
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
