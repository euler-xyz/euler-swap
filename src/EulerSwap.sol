// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IERC20, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";
import {Errors as EVKErrors} from "evk/EVault/shared/Errors.sol";
import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";
import {IEulerSwap} from "./interfaces/IEulerSwap.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Test, console} from "forge-std/Test.sol";
import "uniswap-v3/FullMath.sol";


contract EulerSwap is IEulerSwap, EVCUtil {
    bytes32 public constant curve = keccak256("EulerSwap v1");

    address public immutable vault0;
    address public immutable vault1;
    address public immutable asset0;
    address public immutable asset1;
    address public immutable myAccount;
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

    event EulerSwapCreated(address indexed eulerSwap, address indexed asset0, address indexed asset1);
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
    error BadFee();
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

        require(params.fee < 1e18, BadFee());
        require(IEVault(params.vault0).EVC() == IEVault(params.vault1).EVC(), DifferentEVC());

        address asset0Addr = IEVault(params.vault0).asset();
        address asset1Addr = IEVault(params.vault1).asset();
        require(asset0Addr < asset1Addr, AssetsOutOfOrderOrEqual());

        vault0 = params.vault0;
        vault1 = params.vault1;
        asset0 = asset0Addr;
        asset1 = asset1Addr;
        myAccount = params.myAccount;
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

        emit EulerSwapCreated(address(this), asset0Addr, asset1Addr);
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

    /// @inheritdoc IEulerSwap
    function activate() public {
        require(status != 2, Locked());
        status = 1;

        address permit2 = IEVault(vault0).permit2Address();
        if (permit2 == address(0)) {
            IERC20(asset0).approve(vault0, type(uint256).max);
        } else {
            IERC20(asset0).approve(permit2, type(uint256).max);
            IAllowanceTransfer(permit2).approve(asset0, vault0, type(uint160).max, type(uint48).max);
        }

        permit2 = IEVault(vault1).permit2Address();
        if (permit2 == address(0)) {
            IERC20(asset1).approve(vault1, type(uint256).max);
        } else {
            IERC20(asset1).approve(permit2, type(uint256).max);
            IAllowanceTransfer(permit2).approve(asset1, vault1, type(uint160).max, type(uint48).max);
        }

        IEVC(evc).enableCollateral(myAccount, vault0);
        IEVC(evc).enableCollateral(myAccount, vault1);
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
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IERC4626.withdraw, (avail, to, myAccount)));
            amount -= avail;
        }

        if (amount > 0) {
            IEVC(evc).enableController(myAccount, vault);
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IBorrowing.borrow, (amount, to)));
        }
    }

    function depositAssets(address vault, uint256 amount) internal returns (uint256) {
        try IEVault(vault).deposit(amount, myAccount) {}
        catch (bytes memory reason) {
            require(bytes4(reason) == EVKErrors.E_ZeroShares.selector, DepositFailure(reason));
            return 0;
        }

        if (IEVC(evc).isControllerEnabled(myAccount, vault)) {
            IEVC(evc).call(
                vault, myAccount, 0, abi.encodeCall(IBorrowing.repayWithShares, (type(uint256).max, myAccount))
            );

            if (myDebt(vault) == 0) {
                IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }

        return amount;
    }

    function myDebt(address vault) internal view returns (uint256) {
        return IEVault(vault).debtOf(myAccount);
    }

    function myBalance(address vault) internal view returns (uint256) {
        uint256 shares = IEVault(vault).balanceOf(myAccount);
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

    /// @dev EulerSwap curve definition
    /// Pre-conditions: x <= x0, 1 <= {px,py} <= 1e36, {x0,y0} <= type(uint112).max, c <= 1e18
    function f(uint256 x, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) public pure returns (uint256) {
        return y0 + (Math.mulDiv(px * (x0 - x), c * x + (1e18 - c) * x0, x * 1e18, Math.Rounding.Ceil) + (py - 1)) / py;
    }
       

    /**
    * @notice EulerSwap fInverse Function
    * @notice Computes the inverse of the f() function for solving quadratic liquidity curve equations
    *         as described in the EulerSwap white paper.
    * @dev This function computes the inverse of the liquidity curve equation, solving for `x` given `y`.
    *      The equation is derived from a quadratic formula with the form:
    *      x = (-b + sqrt(b^2 + 4ac)) / 2a
    *      The function uses Uniswap's FullMath to avoid intermediate overflow
    *      and ensures precision by rounding up where necessary.
    *
    * @param y The y-coordinate input value (must be greater than `x0`).
    * @param px The price factor for the x-axis (scaled by `1e18`, must be ≥ `1e18` and ≤ `1e36`).
    * @param py The price factor for the y-axis (scaled by `1e18`, must be ≥ `1e18` and ≤ `1e36`).
    * @param x0 The reference x-value in the liquidity curve equation (must be ≤ `2^112 - 1`).
    * @param y0 The reference y-value in the liquidity curve equation (must be ≤ `2^112 - 1`).
    * @param c The curve parameter that shapes the liquidity curve (scaled by `1e18`, must be > `1e18` and ≤ `1e18`).
    * 
    * @return x The computed inverse value of `x` on the liquidity curve.
    *
    * @custom:precision This function employs rounding up in all calculations to maintain precision.
    * @custom:safety Uses FullMath to handle potential overflow when computing b^2.
    * @custom:requirement The input `y` must be strictly greater than `x0`, otherwise the function will revert.
    */
    function fInverse(
        uint256 y, 
        uint256 px, 
        uint256 py, 
        uint256 x0, 
        uint256 y0, 
        uint256 c
    ) public pure returns (uint256) {
        require(y > x0, "Invalid input coordinate");
        
        // a component of quadratic equation
        uint256 a = 2 * c;

        // b component of quadratic equation
        int256 b = int256((px * (y - x0) + py - 1) / py) - int256((y0 * (2 * c - 1e18) + 1e18 - 1) / 1e18); 

        // b^2 component of quadratic equation
        uint256 bAbs = abs(b); // next step FullMath needs a uint256 so first take absolute value
        uint256 bSquared = FullMath.mulDiv(bAbs, bAbs, 1e18) + (bAbs * bAbs % 1e18 == 0 ? 0 : 1); // use Uniswap FullMath because it handles intermediate overflow if b^2 is too large

        // 4 * a * c component of quadratic equation
        uint256 cPart = Math.mulDiv(4 * c, (1e18 - c), 1e18, Math.Rounding.Ceil);
        uint256 y0Squared = Math.mulDiv(y0, y0, 1e18, Math.Rounding.Ceil);
        uint256 ac4 = Math.mulDiv(cPart, y0Squared, 1e18, Math.Rounding.Ceil);

        // discriminant component of quadratic formula
        uint256 discriminant = bSquared + ac4;

        // square root of the discriminant (rounded up) component of quadratic formula
        uint256 sqrt = sqrtRoundUpSafe(discriminant * 1e18);

        // solve for x = fInverse(y)
        return Math.mulDiv(uint256(int256(sqrt) - b), 1e18, a, Math.Rounding.Ceil);
    }

    /**
    * @notice Computes the square root of a `uint256`, rounding up if necessary.
    * @param x The input value
    * @return The square root of `x`, rounded up.
    */
    function sqrtRoundUpSafe(uint256 x) internal pure returns (uint256) {
        uint256 result = Math.sqrt(x);
        return (result * result < x) ? result + 1 : result;
    }

    /**
    * @notice Returns the absolute value of an `int256` as a `uint256`.
    * @param x The signed integer input
    * @return The absolute value as an unsigned integer.
    */
    function abs(int256 x) internal pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }

}

