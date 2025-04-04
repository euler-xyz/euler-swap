// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";
import {Errors as EVKErrors} from "evk/EVault/shared/Errors.sol";
import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

contract EulerSwap is IEulerSwap, EVCUtil {
    using SafeERC20 for IERC20;

    bytes32 public constant curve = bytes32("EulerSwap v1");

    address public immutable vault0;
    address public immutable vault1;
    address public immutable asset0;
    address public immutable asset1;
    address public immutable eulerAccount;
    uint112 public immutable equilibriumReserve0;
    uint112 public immutable equilibriumReserve1;
    uint256 public immutable fee;
    uint256 public immutable protocolFee;
    address public immutable protocolFeeRecipient;

    uint256 public immutable priceX;
    uint256 public immutable priceY;
    uint256 public immutable concentrationX;
    uint256 public immutable concentrationY;

    uint112 public reserve0;
    uint112 public reserve1;
    uint32 public status; // 0 = unactivated, 1 = unlocked, 2 = locked

    event EulerSwapCreated(address indexed asset0, address indexed asset1);
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
    error Overflow();
    error BadParam();
    error AmountTooBig();
    error AssetsOutOfOrderOrEqual();
    error CurveViolation();
    error DepositFailure(bytes reason);

    modifier nonReentrant() {
        if (status == 0) activate();
        require(status == 1, Locked());
        status = 2;
        _;
        status = 1;
    }

    constructor(Params memory params, CurveParams memory curveParams) EVCUtil(IEVault(params.vault0).EVC()) {
        // EulerSwap params

        require(params.fee < 1e18, BadParam());
        require(curveParams.priceX > 0 && curveParams.priceY > 0, BadParam());
        require(curveParams.priceX <= 1e36 && curveParams.priceY <= 1e36, BadParam());
        require(curveParams.concentrationX <= 1e18 && curveParams.concentrationY <= 1e18, BadParam());

        address asset0Addr = IEVault(params.vault0).asset();
        address asset1Addr = IEVault(params.vault1).asset();
        require(asset0Addr < asset1Addr, AssetsOutOfOrderOrEqual());

        vault0 = params.vault0;
        vault1 = params.vault1;
        asset0 = asset0Addr;
        asset1 = asset1Addr;
        eulerAccount = params.eulerAccount;
        protocolFeeRecipient = params.protocolFeeRecipient;
        equilibriumReserve0 = params.equilibriumReserve0;
        equilibriumReserve1 = params.equilibriumReserve1;
        reserve0 = params.currReserve0;
        reserve1 = params.currReserve1;
        fee = params.fee;
        protocolFee = params.protocolFee;
        protocolFeeRecipient = params.protocolFeeRecipient;

        // Curve params

        priceX = curveParams.priceX;
        priceY = curveParams.priceY;
        concentrationX = curveParams.concentrationX;
        concentrationY = curveParams.concentrationY;

        // Validate reserves

        require(verify(reserve0, reserve1), CurveViolation());
        require(!verify(reserve0 > 0 ? reserve0 - 1 : 0, reserve1), CurveViolation());
        require(!verify(reserve0, reserve1 > 0 ? reserve1 - 1 : 0), CurveViolation());

        emit EulerSwapCreated(asset0Addr, asset1Addr);
    }

    /// @inheritdoc IEulerSwap
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        callThroughEVC
        nonReentrant
    {
        require(amount0Out <= type(uint112).max && amount1Out <= type(uint112).max, AmountTooBig());

        // Optimistically send tokens

        if (amount0Out > 0) withdrawAssets(vault0, amount0Out, to);
        if (amount1Out > 0) withdrawAssets(vault1, amount1Out, to);

        // Invoke callback

        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(_msgSender(), amount0Out, amount1Out, data);

        // Deposit all available funds, adjust received amounts downward to collect fees

        uint256 amount0In = depositAssets(asset0, vault0);
        uint256 amount1In = depositAssets(asset1, vault1);

        // Verify curve invariant is satisfied

        {
            uint256 newReserve0 = reserve0 + amount0In - amount0Out;
            uint256 newReserve1 = reserve1 + amount1In - amount1Out;

            require(verify(newReserve0, newReserve1), CurveViolation());

            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);

            emit Swap(
                _msgSender(),
                amount0In,
                amount1In,
                amount0Out,
                amount1Out,
                uint112(newReserve0),
                uint112(newReserve1),
                to
            );
        }
    }

    /// @inheritdoc IEulerSwap
    function getReserves() external view returns (uint112, uint112, uint32) {
        require(status != 2, Locked());
        return (reserve0, reserve1, status);
    }

    /// @inheritdoc IEulerSwap
    function EVC() external view override(EVCUtil, IEulerSwap) returns (address) {
        return address(evc);
    }

    /// @inheritdoc IEulerSwap
    function activate() public {
        require(status != 2, Locked());
        status = 1;

        approveVault(asset0, vault0);
        approveVault(asset1, vault1);

        IEVC(evc).enableCollateral(eulerAccount, vault0);
        IEVC(evc).enableCollateral(eulerAccount, vault1);
    }

    /// @inheritdoc IEulerSwap
    function verify(uint256 newReserve0, uint256 newReserve1) public view returns (bool) {
        if (newReserve0 > type(uint112).max || newReserve1 > type(uint112).max) return false;

        if (newReserve0 >= equilibriumReserve0) {
            if (newReserve1 >= equilibriumReserve1) return true;
            return
                newReserve0 >= f(newReserve1, priceY, priceX, equilibriumReserve1, equilibriumReserve0, concentrationY);
        } else {
            if (newReserve1 < equilibriumReserve1) return false;
            return
                newReserve1 >= f(newReserve0, priceX, priceY, equilibriumReserve0, equilibriumReserve1, concentrationX);
        }
    }

    /// @notice Withdraws assets from a vault, first using available balance and then borrowing if needed
    /// @param vault The address of the vault to withdraw from
    /// @param amount The total amount of assets to withdraw
    /// @param to The address that will receive the withdrawn assets
    /// @dev This function first checks if there's an existing balance in the vault.
    /// @dev If there is, it withdraws the minimum of the requested amount and available balance.
    /// @dev If more assets are needed after withdrawal, it enables the controller and borrows the remaining amount.
    function withdrawAssets(address vault, uint256 amount, address to) internal {
        uint256 balance = myBalance(vault);

        if (balance > 0) {
            uint256 avail = amount < balance ? amount : balance;
            IEVC(evc).call(vault, eulerAccount, 0, abi.encodeCall(IERC4626.withdraw, (avail, to, eulerAccount)));
            amount -= avail;
        }

        if (amount > 0) {
            IEVC(evc).enableController(eulerAccount, vault);
            IEVC(evc).call(vault, eulerAccount, 0, abi.encodeCall(IBorrowing.borrow, (amount, to)));
        }
    }

    /// @notice Deposits assets into a vault and automatically repays any outstanding debt
    /// @param asset The address of the underlying asset
    /// @param vault The address of the vault to deposit into
    /// @return The amount of assets successfully deposited
    /// @dev This function attempts to deposit assets into the specified vault.
    /// @dev If the deposit fails with E_ZeroShares error, it safely returns 0 (this happens with very small amounts).
    /// @dev After successful deposit, if the user has any outstanding controller-enabled debt, it attempts to repay it.
    /// @dev If all debt is repaid, the controller is automatically disabled to reduce gas costs in future operations.
    function depositAssets(address asset, address vault) internal returns (uint256) {
        uint256 amount = IERC20(asset).balanceOf(address(this));
        if (amount == 0) return 0;

        uint256 feeAmount = amount * fee / 1e18;

        {
            uint256 protocolFeeAmount = feeAmount * protocolFee / 1e18;

            if (protocolFeeAmount != 0) {
                IERC20(asset).transfer(protocolFeeRecipient, protocolFeeAmount);
                amount -= protocolFeeAmount;
                feeAmount -= protocolFeeAmount;
            }
        }

        uint256 deposited;

        if (IEVC(evc).isControllerEnabled(eulerAccount, vault)) {
            uint256 debt = myDebt(vault);
            uint256 repaid = IEVault(vault).repay(amount > debt ? debt : amount, eulerAccount);

            amount -= repaid;
            debt -= repaid;
            deposited += repaid;

            if (debt == 0) {
                IEVC(evc).call(vault, eulerAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }

        if (amount > 0) {
            try IEVault(vault).deposit(amount, eulerAccount) {}
            catch (bytes memory reason) {
                require(bytes4(reason) == EVKErrors.E_ZeroShares.selector, DepositFailure(reason));
                amount = 0;
            }

            deposited += amount;
        }

        return deposited > feeAmount ? deposited - feeAmount : 0;
    }

    /// @notice Approves tokens for a given vault, supporting both standard approvals and permit2
    /// @param asset The address of the token to approve
    /// @param vault The address of the vault to approve the token for
    function approveVault(address asset, address vault) internal {
        address permit2 = IEVault(vault).permit2Address();
        if (permit2 == address(0)) {
            IERC20(asset).forceApprove(vault, type(uint256).max);
        } else {
            IERC20(asset).forceApprove(permit2, type(uint256).max);
            IAllowanceTransfer(permit2).approve(asset, vault, type(uint160).max, type(uint48).max);
        }
    }

    /// @notice Retrieves the current debt amount for the pool's eulerAccount
    /// @param vault The address of the vault to check for debt
    /// @return The amount of debt that the Euler account has in the specified vault
    function myDebt(address vault) internal view returns (uint256) {
        return IEVault(vault).debtOf(eulerAccount);
    }

    /// @notice Calculates the asset balance of the pool's eulerAccount
    /// @param vault The address of the vault to check for balance
    /// @return The amount of assets that the Euler account has deposited in the specified vault
    function myBalance(address vault) internal view returns (uint256) {
        uint256 shares = IEVault(vault).balanceOf(eulerAccount);
        return shares == 0 ? 0 : IEVault(vault).convertToAssets(shares);
    }

    /// @dev EulerSwap curve definition
    /// Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);
            require(v <= type(uint248).max, Overflow());
            return y0 + (v + (py - 1)) / py;
        }
    }
}
