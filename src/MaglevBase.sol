// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IMaglevBase} from "./interfaces/IMaglevBase.sol";
import {console} from "forge-std/Test.sol";
import {Ownable, Context} from "openzeppelin-contracts/access/Ownable.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IERC20, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";
import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";

abstract contract MaglevBase is IMaglevBase, EVCUtil, Ownable {
    error Reentrancy();
    error Overflow();
    error UnsupportedPair();
    error InsufficientReserves();
    error InsufficientCash();

    uint32 private locked;

    address public immutable vault0;
    address public immutable vault1;
    address public immutable asset0;
    address public immutable asset1;
    address public immutable myAccount;

    uint112 public reserve0;
    uint112 public reserve1;
    uint112 public initialReserve0;
    uint112 public initialReserve1;

    struct BaseParams {
        address evc;
        address vault0;
        address vault1;
        address myAccount;
    }

    constructor(BaseParams memory params) EVCUtil(params.evc) Ownable(msg.sender) {
        vault0 = params.vault0;
        vault1 = params.vault1;
        asset0 = IEVault(vault0).asset();
        asset1 = IEVault(vault1).asset();
        myAccount = params.myAccount;
    }

    modifier nonReentrant() {
        require(locked == 0, Reentrancy());
        locked = 1;
        _;
        locked = 0;
    }

    // Owner functions

    /// @dev Call *after* installing as operator
    function configure() external onlyOwner {
        IERC20(asset0).approve(vault0, type(uint256).max);
        IERC20(asset1).approve(vault1, type(uint256).max);

        IEVC(evc).enableCollateral(myAccount, vault0);
        IEVC(evc).enableCollateral(myAccount, vault1);
    }

    function setDebtLimit(uint112 debtLimit0, uint112 debtLimit1) external onlyOwner {
        reserve0 = initialReserve0 = adjustReserve(debtLimit0, vault0);
        reserve1 = initialReserve1 = adjustReserve(debtLimit1, vault1);
    }

    // Swapper interface

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        callThroughEVC
        nonReentrant
    {
        // Optimistically send tokens

        if (amount0Out > 0) withdrawAssets(vault0, amount0Out, to);
        if (amount1Out > 0) withdrawAssets(vault1, amount1Out, to);

        // Invoke callback

        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);

        // Deposit all available funds

        uint256 amount0In = IERC20(asset0).balanceOf(address(this));
        uint256 amount1In = IERC20(asset1).balanceOf(address(this));
        if (amount0In > 0) depositAssets(vault0, amount0In);
        if (amount1In > 0) depositAssets(vault1, amount1In);

        // Verify curve invariant is satisified

        {
            uint256 newReserve0 = reserve0 + amount0In - amount0Out;
            uint256 newReserve1 = reserve1 + amount1In - amount1Out;

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, Overflow());
            verify(amount0In, amount1In, newReserve0, newReserve1);

            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);
        }
    }

    function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256) {
        return _computeQuote(tokenIn, tokenOut, amountIn, true);
    }

    function quoteExactOutput(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256) {
        return _computeQuote(tokenIn, tokenOut, amountOut, false);
    }

    // Internal utilities

    function withdrawAssets(address vault, uint256 amount, address to) internal {
        uint256 balance = myBalance(vault);

        if (balance > 0) {
            uint256 avail = amount < balance ? amount : balance;
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IERC4626.withdraw, (avail, to, myAccount)));
            amount -= avail;
        }

        if (amount > 0) {
            IEVC(evc).enableController(myAccount, vault);
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IBorrowing.borrow, (amount, to)));
        }
    }

    function depositAssets(address vault, uint256 amount) internal {
        IEVault(vault).deposit(amount, myAccount);

        uint256 debt = myDebt(vault);

        if (debt > 0) {
            IEVC(evc).call(
                vault, myAccount, 0, abi.encodeCall(IBorrowing.repayWithShares, (type(uint256).max, myAccount))
            );

            if (debt <= amount) {
                IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }
    }

    function _msgSender() internal view override(Context, EVCUtil) returns (address) {
        return EVCUtil._msgSender();
    }


    function myDebt(address vault) internal view returns (uint256) {
        return IEVault(vault).debtOf(myAccount);
    }

    function myBalance(address vault) internal view returns (uint256) {
        uint256 shares = IEVault(vault).balanceOf(myAccount);
        return shares == 0 ? 0 : IEVault(vault).convertToAssets(shares);
    }

    function adjustReserve(uint112 reserve, address vault) internal view returns (uint112) {
        uint256 adjusted;
        uint256 debt = myDebt(vault);

        if (debt != 0) {
            adjusted = reserve > debt ? reserve - debt : 0;
        } else {
            adjusted = reserve + myBalance(vault);
        }

        require(adjusted <= type(uint112).max, Overflow());
        return uint112(adjusted);
    }

    function _computeQuote(address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        internal
        view
        returns (uint256)
    {
        bool asset0IsInput;
        if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
        else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
        else revert UnsupportedPair();

        uint256 quote = computeQuote(amount, exactIn, asset0IsInput);

        require(quote <= (asset0IsInput ? reserve1 : reserve0), InsufficientReserves());
        require(
            quote <= IERC20(asset0IsInput ? asset1 : asset0).balanceOf(asset0IsInput ? vault1 : vault0),
            InsufficientCash()
        );

        return quote;
    }

    // To be implemented by sub-class

    function verify(uint256 amount0In, uint256 amount1In, uint256 newReserve0, uint256 newReserve1)
        internal
        view
        virtual;

    function computeQuote(uint256 amount, bool exactIn, bool asset0IsInput) internal view virtual returns (uint256);
}
