// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEulerSwapPeriphery} from "./interfaces/IEulerSwapPeriphery.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";

contract EulerSwapPeriphery is IEulerSwapPeriphery {
    using SafeERC20 for IERC20;

    error AmountOutLessThanMin();
    error AmountInMoreThanMax();
    error UnexpectedAmountOut();
    error DeadlineExpired();

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactIn(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        uint256 amountOutMin,
        uint256 deadline
    ) external {
        require(deadline == 0 || deadline >= block.timestamp, DeadlineExpired());

        uint256 amountOut = IEulerSwap(eulerSwap).computeQuote(tokenIn, tokenOut, amountIn, true);

        require(amountOut >= amountOutMin, AmountOutLessThanMin());
        swap(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, amountOut, receiver);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function swapExactOut(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        address receiver,
        uint256 amountInMax,
        uint256 deadline
    ) external {
        require(deadline == 0 || deadline >= block.timestamp, DeadlineExpired());

        uint256 amountIn = IEulerSwap(eulerSwap).computeQuote(tokenIn, tokenOut, amountOut, false);

        require(amountIn <= amountInMax, AmountInMoreThanMax());

        swap(IEulerSwap(eulerSwap), tokenIn, tokenOut, amountIn, amountOut, receiver);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256)
    {
        return IEulerSwap(eulerSwap).computeQuote(tokenIn, tokenOut, amountIn, true);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut)
        external
        view
        returns (uint256)
    {
        return IEulerSwap(eulerSwap).computeQuote(tokenIn, tokenOut, amountOut, false);
    }

    /// @inheritdoc IEulerSwapPeriphery
    function getLimits(address eulerSwap, address tokenIn, address tokenOut) external view returns (uint256, uint256) {
        return IEulerSwap(eulerSwap).getLimits(tokenIn, tokenOut);
    }

    /// @dev Internal function to execute a token swap through EulerSwap
    /// @param eulerSwap The EulerSwap contract address to execute the swap through
    /// @param tokenIn The address of the input token being swapped
    /// @param tokenOut The address of the output token being received
    /// @param amountIn The amount of input tokens to swap
    /// @param amountOut The amount of output tokens to receive
    /// @param receiver The address that should receive the swap output
    function swap(
        IEulerSwap eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address receiver
    ) internal {
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(receiver);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(eulerSwap), amountIn);

        bool isAsset0In = tokenIn < tokenOut;
        (isAsset0In) ? eulerSwap.swap(0, amountOut, receiver, "") : eulerSwap.swap(amountOut, 0, receiver, "");

        require(IERC20(tokenOut).balanceOf(receiver) == balanceBefore + amountOut, UnexpectedAmountOut());
    }
}
