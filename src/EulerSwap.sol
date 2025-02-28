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
       

    function fInverse(uint x, uint px, uint py, uint x0, uint y0, uint c) public pure returns (uint){
        require(x > x0, "Invalid input coordinate");
        // intermediate values for solving quadratic equation
        uint256 a = c;
        int256 part1 = int256(y0) * (int256(2 * c)  - 1e18) / 1e18;
        console.log("part1", part1);

        // xt > x0
        uint256 part2 = px * (x - x0) / py;
        console.log("part2", part2);

        int256 part3 = int256(part1 - int256(part2)); 
        uint256 part3abs = abs(part3);
        console.log("part3", part3);

        uint256 part3Squared = Math.mulDiv(part3abs, part3abs, 1e18);
        console.log("part3squared", part3Squared);

        uint256 part4 = 4 * Math.mulDiv(Math.mulDiv(c, (1e18 - c), 1e18), Math.mulDiv(y0, y0, 1e18), 1e18);
        console.log("part4", part4);

        uint256 discriminant = part3Squared + part4;
        console.log("discriminant", discriminant);

        uint256 sqrt = sqrtRoundUpSafe(discriminant * 1e18);
        console.log("sqrt: ", sqrt);

        uint256 numerator = uint256(int256(sqrt) + part3);
        console.log("numerator", numerator);

        uint256 denominator = 2 * c;
        console.log("part1", denominator);

        // // int b = int(Math.mulDiv(px * 1e18, (xt - x0), py)) + int(Math.mulDiv(y0, int(1e18) - 2 * c, 1e18));
        // int d = (int(c) - 1e18) * int(y0)**2 / 1e18 / 1e18;
        // uint discriminant = uint(int(uint(b**2) / 1e18) - 4 * int(a) * int(d) / 1e18);
        // uint numerator = uint(int(uint(Math.sqrt(discriminant) * 1e9)) - b);
        // uint denominator = 2 * a;
        return Math.mulDiv(numerator, 1e18, denominator);
    }

    function sqrtRoundUpSafe(uint256 x) internal pure returns (uint256) {
        uint256 result = Math.sqrt(x);
        return (Math.mulDiv(result, result, 1) < x) ? result + 1 : result;
    }

    function abs(int256 x) internal pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }


}

