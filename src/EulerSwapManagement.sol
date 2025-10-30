// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IEulerSwapCallee} from "./interfaces/IEulerSwapCallee.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";

import {EulerSwapBase} from "./EulerSwapBase.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {CtxLib} from "./libraries/CtxLib.sol";
import {FundsLib} from "./libraries/FundsLib.sol";
import {CurveLib} from "./libraries/CurveLib.sol";
import {SwapLib} from "./libraries/SwapLib.sol";

contract EulerSwapManagement is EulerSwapBase {
    error Unauthorized();
    error AlreadyActivated();
    error BadStaticParam();
    error BadDynamicParam();
    error AmountTooBig();
    error AssetsOutOfOrderOrEqual();
    error InvalidAssets();

    /// @notice Emitted upon EulerSwap instance creation or reconfiguration.
    event EulerSwapConfigured(IEulerSwap.DynamicParams dParams, IEulerSwap.InitialState initialState);
    /// @notice Emitted upon EulerSwap instance creation or reconfiguration.
    event EulerSwapManagerSet(address indexed manager, bool installed);

    constructor(address evc_) EulerSwapBase(evc_) {}

    function installDynamicParams(
        CtxLib.State storage s,
        IEulerSwap.DynamicParams memory dParams,
        IEulerSwap.InitialState memory initialState
    ) internal {
        require(dParams.minReserve0 <= dParams.equilibriumReserve0, BadDynamicParam());
        require(dParams.minReserve1 <= dParams.equilibriumReserve1, BadDynamicParam());
        require(dParams.minReserve0 <= initialState.reserve0, BadDynamicParam());
        require(dParams.minReserve1 <= initialState.reserve1, BadDynamicParam());

        require(dParams.priceX > 0 && dParams.priceY > 0, BadDynamicParam());
        require(dParams.priceX <= 1e24 && dParams.priceY <= 1e24, BadDynamicParam());
        require(dParams.concentrationX <= 1e18 && dParams.concentrationY <= 1e18, BadDynamicParam());

        require(dParams.fee0 <= 1e18 && dParams.fee1 <= 1e18, BadDynamicParam());

        require(dParams.swapHookedOperations <= 7, BadDynamicParam());
        require(dParams.swapHookedOperations == 0 || dParams.swapHook != address(0), BadDynamicParam());

        require(CurveLib.verify(dParams, initialState.reserve0, initialState.reserve1), SwapLib.CurveViolation());

        CtxLib.writeDynamicParamsToStorage(dParams);
        s.reserve0 = initialState.reserve0;
        s.reserve1 = initialState.reserve1;

        emit EulerSwapConfigured(dParams, initialState);
    }

    function activate(IEulerSwap.DynamicParams calldata dParams, IEulerSwap.InitialState calldata initialState)
        external
    {
        CtxLib.State storage s = CtxLib.getState();
        IEulerSwap.StaticParams memory sParams = CtxLib.getStaticParams();

        require(s.status == 0, AlreadyActivated());
        s.status = 1;

        // Static parameters

        {
            address asset0Addr = IEVault(sParams.supplyVault0).asset();
            address asset1Addr = IEVault(sParams.supplyVault1).asset();

            require(
                sParams.borrowVault0 == address(0) || IEVault(sParams.borrowVault0).asset() == asset0Addr,
                InvalidAssets()
            );
            require(
                sParams.borrowVault1 == address(0) || IEVault(sParams.borrowVault1).asset() == asset1Addr,
                InvalidAssets()
            );

            require(asset0Addr != address(0) && asset1Addr != address(0), InvalidAssets());
            require(asset0Addr < asset1Addr, AssetsOutOfOrderOrEqual());
        }

        require(sParams.eulerAccount != sParams.feeRecipient, BadStaticParam()); // set feeRecipient to 0 instead

        // Dynamic parameters

        if (initialState.reserve0 != 0) {
            require(
                !CurveLib.verify(dParams, initialState.reserve0 - 1, initialState.reserve1), SwapLib.CurveViolation()
            );
        }
        if (initialState.reserve1 != 0) {
            require(
                !CurveLib.verify(dParams, initialState.reserve0, initialState.reserve1 - 1), SwapLib.CurveViolation()
            );
        }

        installDynamicParams(s, dParams, initialState);

        // Configure external contracts

        FundsLib.approveVault(sParams.supplyVault0);
        FundsLib.approveVault(sParams.supplyVault1);

        if (sParams.borrowVault0 != address(0) && sParams.borrowVault0 != sParams.supplyVault0) {
            FundsLib.approveVault(sParams.borrowVault0);
        }
        if (sParams.borrowVault1 != address(0) && sParams.borrowVault1 != sParams.supplyVault1) {
            FundsLib.approveVault(sParams.borrowVault1);
        }

        if (
            !IEVC(evc).isCollateralEnabled(sParams.eulerAccount, sParams.supplyVault0)
                && sParams.borrowVault1 != address(0)
        ) {
            IEVC(evc).enableCollateral(sParams.eulerAccount, sParams.supplyVault0);
        }
        if (
            !IEVC(evc).isCollateralEnabled(sParams.eulerAccount, sParams.supplyVault1)
                && sParams.borrowVault0 != address(0)
        ) {
            IEVC(evc).enableCollateral(sParams.eulerAccount, sParams.supplyVault1);
        }
    }

    function setManager(address manager, bool installed) external nonReentrant {
        CtxLib.State storage s = CtxLib.getState();
        IEulerSwap.StaticParams memory sParams = CtxLib.getStaticParams();

        require(_msgSender() == sParams.eulerAccount, Unauthorized());
        s.managers[manager] = installed;

        emit EulerSwapManagerSet(manager, installed);
    }

    function reconfigure(IEulerSwap.DynamicParams calldata dParams, IEulerSwap.InitialState calldata initialState)
        external
        nonReentrant
    {
        CtxLib.State storage s = CtxLib.getState();
        IEulerSwap.StaticParams memory sParams = CtxLib.getStaticParams();
        IEulerSwap.DynamicParams memory oldDParams = CtxLib.getDynamicParams();

        {
            address sender = _msgSender();
            require(
                sender == sParams.eulerAccount || s.managers[sender] || sender == oldDParams.swapHook, Unauthorized()
            );
        }

        installDynamicParams(s, dParams, initialState);
    }
}
