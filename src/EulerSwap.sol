// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";

import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";

import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {UniswapHook} from "./UniswapHook.sol";
import {CtxLib} from "./libraries/CtxLib.sol";
import {FundsLib} from "./libraries/FundsLib.sol";
import {CurveLib} from "./libraries/CurveLib.sol";
import {QuoteLib} from "./libraries/QuoteLib.sol";

contract EulerSwap is IEulerSwap, EVCUtil, UniswapHook {
    bytes32 public constant curve = bytes32("EulerSwap v1");

    event EulerSwapActivated(address indexed asset0, address indexed asset1);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        uint112 reserve0,
        uint112 reserve1,
        address indexed to
    );

    error Locked();
    error AlreadyActivated();
    error BadParam();
    error AmountTooBig();
    error AssetsOutOfOrderOrEqual();

    constructor(address evc_, address poolManager_) EVCUtil(evc_) UniswapHook(evc_, poolManager_) {
        CtxLib.Storage storage s = CtxLib.getStorage();

        s.status = 2; // can only be used via delegatecall proxy
    }

    modifier nonReentrant() {
        CtxLib.Storage storage s = CtxLib.getStorage();

        require(s.status == 1, Locked());
        s.status = 2;
        _;
        s.status = 1;
    }

    modifier nonReentrantView() {
        CtxLib.Storage storage s = CtxLib.getStorage();
        require(s.status != 2, Locked());

        _;
    }

    /// @inheritdoc IEulerSwap
    function activate(InitialState calldata initialState) external {
        CtxLib.Storage storage s = CtxLib.getStorage();
        Params memory p = CtxLib.getParams();

        require(s.status == 0, AlreadyActivated());
        s.status = 1;

        // Parameter validation

        require(p.fee < 1e18, BadParam());
        require(p.priceX > 0 && p.priceY > 0, BadParam());
        require(p.priceX <= 1e36 && p.priceY <= 1e36, BadParam());
        require(p.concentrationX > 0 && p.concentrationY > 0, BadParam());
        require(p.concentrationX <= 1e18 && p.concentrationY <= 1e18, BadParam());

        {
            address asset0Addr = IEVault(p.vault0).asset();
            address asset1Addr = IEVault(p.vault1).asset();
            require(asset0Addr < asset1Addr, AssetsOutOfOrderOrEqual());
            emit EulerSwapActivated(asset0Addr, asset1Addr);
        }

        // Initial state

        s.reserve0 = initialState.currReserve0;
        s.reserve1 = initialState.currReserve1;

        require(CurveLib.verify(p, s.reserve0, s.reserve1), CurveLib.CurveViolation());
        if (s.reserve0 != 0) require(!CurveLib.verify(p, s.reserve0 - 1, s.reserve1), CurveLib.CurveViolation());
        if (s.reserve1 != 0) require(!CurveLib.verify(p, s.reserve0, s.reserve1 - 1), CurveLib.CurveViolation());

        // Configure external contracts

        FundsLib.approveVault(p.vault0);
        FundsLib.approveVault(p.vault1);

        IEVC(evc).enableCollateral(p.eulerAccount, p.vault0);
        IEVC(evc).enableCollateral(p.eulerAccount, p.vault1);

        // Uniswap hooks

        if (address(poolManager) != address(0)) activateHook(p);
    }

    /// @inheritdoc IEulerSwap
    function getParams() external pure returns (Params memory) {
        return CtxLib.getParams();
    }

    /// @inheritdoc IEulerSwap
    function getAssets() external view returns (address asset0, address asset1) {
        Params memory p = CtxLib.getParams();

        asset0 = IEVault(p.vault0).asset();
        asset1 = IEVault(p.vault1).asset();
    }

    /// @inheritdoc IEulerSwap
    function getReserves() external view nonReentrantView returns (uint112, uint112, uint32) {
        CtxLib.Storage storage s = CtxLib.getStorage();

        return (s.reserve0, s.reserve1, s.status);
    }

    /// @inheritdoc IEulerSwap
    function computeQuote(address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        external
        view
        nonReentrantView
        returns (uint256)
    {
        Params memory p = CtxLib.getParams();

        return QuoteLib.computeQuote(address(evc), p, QuoteLib.checkTokens(p, tokenIn, tokenOut), amount, exactIn);
    }

    /// @inheritdoc IEulerSwap
    function getLimits(address tokenIn, address tokenOut) external view nonReentrantView returns (uint256, uint256) {
        Params memory p = CtxLib.getParams();

        if (!evc.isAccountOperatorAuthorized(p.eulerAccount, address(this))) return (0, 0);

        return QuoteLib.calcLimits(p, QuoteLib.checkTokens(p, tokenIn, tokenOut));
    }

    /// @inheritdoc IEulerSwap
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        callThroughEVC
        nonReentrant
    {
        require(amount0Out <= type(uint112).max && amount1Out <= type(uint112).max, AmountTooBig());

        CtxLib.Storage storage s = CtxLib.getStorage();
        Params memory p = CtxLib.getParams();

        // Optimistically send tokens

        if (amount0Out > 0) FundsLib.withdrawAssets(address(evc), p, p.vault0, amount0Out, to);
        if (amount1Out > 0) FundsLib.withdrawAssets(address(evc), p, p.vault1, amount1Out, to);

        // Invoke callback

        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(_msgSender(), amount0Out, amount1Out, data);

        // Deposit all available funds, adjust received amounts downward to collect fees

        uint256 amount0In = FundsLib.depositAssets(address(evc), p, p.vault0);
        uint256 amount1In = FundsLib.depositAssets(address(evc), p, p.vault1);

        // Verify curve invariant is satisfied

        {
            uint256 newReserve0 = s.reserve0 + amount0In - amount0Out;
            uint256 newReserve1 = s.reserve1 + amount1In - amount1Out;

            require(CurveLib.verify(p, newReserve0, newReserve1), CurveLib.CurveViolation());

            s.reserve0 = uint112(newReserve0);
            s.reserve1 = uint112(newReserve1);
        }

        emit Swap(_msgSender(), amount0In, amount1In, amount0Out, amount1Out, s.reserve0, s.reserve1, to);
    }
}
