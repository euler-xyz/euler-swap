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

    bytes32 public constant curve = keccak256("EulerSwap v1");

    address public immutable vault0;
    address public immutable vault1;
    address public immutable asset0;
    address public immutable asset1;
    address public immutable eulerAccount;
    uint112 public immutable debtLimit0;
    uint112 public immutable debtLimit1;
    uint112 public immutable initialReserve0;
    uint112 public immutable initialReserve1;
    uint256 public immutable feeMultiplier;

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
    error DifferentEVC();
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
        require(params.debtLimit0 <= type(uint112).max && params.debtLimit1 <= type(uint112).max, BadParam());
        require(curveParams.priceX > 0 && curveParams.priceY > 0, BadParam());
        require(curveParams.priceX <= 1e36 && curveParams.priceY <= 1e36, BadParam());
        require(curveParams.concentrationX <= 1e18 && curveParams.concentrationY <= 1e18, BadParam());
        require(IEVault(params.vault0).EVC() == IEVault(params.vault1).EVC(), DifferentEVC());

        address asset0Addr = IEVault(params.vault0).asset();
        address asset1Addr = IEVault(params.vault1).asset();
        require(asset0Addr < asset1Addr, AssetsOutOfOrderOrEqual());

        vault0 = params.vault0;
        vault1 = params.vault1;
        asset0 = asset0Addr;
        asset1 = asset1Addr;
        eulerAccount = params.eulerAccount;
        debtLimit0 = params.debtLimit0;
        debtLimit1 = params.debtLimit1;
        initialReserve0 = reserve0 = offsetReserve(params.debtLimit0, params.vault0);
        initialReserve1 = reserve1 = offsetReserve(params.debtLimit1, params.vault1);
        feeMultiplier = 1e18 - params.fee;

        // Curve params

        priceX = curveParams.priceX;
        priceY = curveParams.priceY;
        concentrationX = curveParams.concentrationX;
        concentrationY = curveParams.concentrationY;

        emit EulerSwapCreated(asset0Addr, asset1Addr);
    }

    /// @inheritdoc IEulerSwap
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        callThroughEVC
        nonReentrant
    {
        // Optimistically send tokens

        if (amount0Out > 0) withdrawAssets(vault0, amount0Out, to);
        if (amount1Out > 0) withdrawAssets(vault1, amount1Out, to);

        // Invoke callback

        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(_msgSender(), amount0Out, amount1Out, data);

        // Deposit all available funds, adjust received amounts downward to collect fees

        uint256 amount0In = IERC20(asset0).balanceOf(address(this));
        if (amount0In > 0) amount0In = depositAssets(vault0, amount0In) * feeMultiplier / 1e18;

        uint256 amount1In = IERC20(asset1).balanceOf(address(this));
        if (amount1In > 0) amount1In = depositAssets(vault1, amount1In) * feeMultiplier / 1e18;

        // Verify curve invariant is satisified

        {
            uint256 newReserve0 = reserve0 + amount0In - amount0Out;
            uint256 newReserve1 = reserve1 + amount1In - amount1Out;

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, Overflow());
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

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, status);
    }

    /// @notice Returns the address of the Ethereum Vault Connector (EVC) used by this contract.
    /// @return The address of the EVC contract.
    function EVC() external view override(EVCUtil, IEulerSwap) returns (address) {
        return address(evc);
    }

    /// @inheritdoc IEulerSwap
    function activate() public {
        require(status != 2, Locked());
        status = 1;

        address permit2 = IEVault(vault0).permit2Address();
        if (permit2 == address(0)) {
            IERC20(asset0).forceApprove(vault0, type(uint256).max);
        } else {
            IERC20(asset0).forceApprove(permit2, type(uint256).max);
            IAllowanceTransfer(permit2).approve(asset0, vault0, type(uint160).max, type(uint48).max);
        }

        permit2 = IEVault(vault1).permit2Address();
        if (permit2 == address(0)) {
            IERC20(asset1).forceApprove(vault1, type(uint256).max);
        } else {
            IERC20(asset1).forceApprove(permit2, type(uint256).max);
            IAllowanceTransfer(permit2).approve(asset1, vault1, type(uint160).max, type(uint48).max);
        }

        IEVC(evc).enableCollateral(eulerAccount, vault0);
        IEVC(evc).enableCollateral(eulerAccount, vault1);
    }

    /// @inheritdoc IEulerSwap
    function verify(uint256 newReserve0, uint256 newReserve1) public view returns (bool) {
        if (newReserve0 >= initialReserve0) {
            if (newReserve1 >= initialReserve1) return true;
            return newReserve0 >= f(newReserve1, priceY, priceX, initialReserve1, initialReserve0, concentrationY);
        } else {
            if (newReserve1 < initialReserve1) return false;
            return newReserve1 >= f(newReserve0, priceX, priceY, initialReserve0, initialReserve1, concentrationX);
        }
    }

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

    function depositAssets(address vault, uint256 amount) internal returns (uint256) {
        try IEVault(vault).deposit(amount, eulerAccount) {}
        catch (bytes memory reason) {
            require(bytes4(reason) == EVKErrors.E_ZeroShares.selector, DepositFailure(reason));
            return 0;
        }

        if (IEVC(evc).isControllerEnabled(eulerAccount, vault)) {
            IEVC(evc).call(
                vault, eulerAccount, 0, abi.encodeCall(IBorrowing.repayWithShares, (type(uint256).max, eulerAccount))
            );

            if (myDebt(vault) == 0) {
                IEVC(evc).call(vault, eulerAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }

        return amount;
    }

    function myDebt(address vault) internal view returns (uint256) {
        return IEVault(vault).debtOf(eulerAccount);
    }

    function myBalance(address vault) internal view returns (uint256) {
        uint256 shares = IEVault(vault).balanceOf(eulerAccount);
        return shares == 0 ? 0 : IEVault(vault).convertToAssets(shares);
    }

    function offsetReserve(uint112 reserve, address vault) internal view returns (uint112) {
        uint256 offset;
        uint256 debt = myDebt(vault);

        if (debt != 0) {
            offset = reserve > debt ? reserve - debt : 0;
        } else {
            offset = reserve + myBalance(vault);
        }

        require(offset <= type(uint112).max, Overflow());
        return uint112(offset);
    }

    /**
     * @notice Computes the y-coordinate on the EulerSwap AMM curve given the x-coordinate.
     * @dev Implements the EulerSwap AMM curve equation f().
     * @param x The x-coordinate input value (must be less than or equal to `x0`).
     * @param px Price factor for the x-axis (scaled by 1e18, between 1e18 and 1e36).
     * @param py Price factor for the y-axis (scaled by 1e18, between 1e18 and 1e36).
     * @param x0 Reference x-value on the AMM curve (≤ 2^112 - 1).
     * @param y0 Reference y-value on the AMM curve (≤ 2^112 - 1).
     * @param c Curve parameter shaping liquidity concentration (scaled by 1e18, between 0 and 1e18).
     *
     * @return y The computed y-coordinate on the AMM curve.
     *
     * @custom:precision Uses rounding up to maintain precision in all calculations.
     * @custom:safety The `require` statement ensures `v` does not exceed the `uint248` limit.
     * @custom:requirement Input `x` must be less than or equal to `x0`; otherwise, the function will revert.
     */
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        unchecked {
            // Intermediate value v using the AMM curve formula
            uint256 v = Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil);

            // Overflow safety check, v must fit within 248 bits
            require(v <= type(uint248).max, Overflow());

            // Calculate and return the final y-coordinate
            return y0 + (v + (py - 1)) / py;
        }
    }
}
