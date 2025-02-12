// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IERC20, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";
import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";
import {IMaglev} from "./interfaces/IMaglev.sol";

contract Maglev is IMaglev, EVCUtil {
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

    error Locked();
    error Overflow();
    error BadFee();
    error DifferentEVC();
    error AssetsOutOfOrderOrEqual();
    error CurveViolation();

    event MaglevCreated(
        address indexed maglev,
        address indexed asset0,
        address indexed asset1
    );

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

    modifier nonReentrant() {
        if (status == 0) activate();
        require(status == 1, Locked());
        status = 2;
        _;
        status = 1;
    }

    struct Params {
        address evc;
        address vault0;
        address vault1;
        address myAccount;
        uint112 debtLimit0;
        uint112 debtLimit1;
        uint256 fee;
    }

    struct CurveParams {
        uint256 priceX;
        uint256 priceY;
        uint256 concentrationX;
        uint256 concentrationY;
    }

    constructor(Params memory params, CurveParams memory curveParams) EVCUtil(params.evc) {
        // Maglev params

        require(params.fee < 1e18, BadFee());

        address vault0Evc = IEVault(params.vault0).EVC();
        require(vault0Evc == IEVault(params.vault1).EVC(), DifferentEVC());
        require(vault0Evc == params.evc, DifferentEVC());

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

        emit MaglevCreated(address(this), asset0Addr, asset1Addr);
    }

    /// @inheritdoc IMaglev
    function activate() public {
        require(status != 2, Locked());
        status = 1;

        IERC20(asset0).approve(vault0, type(uint256).max);
        IERC20(asset1).approve(vault1, type(uint256).max);

        IEVC(evc).enableCollateral(myAccount, vault0);
        IEVC(evc).enableCollateral(myAccount, vault1);
    }

    /// @dev EulerSwap curve definition
    function f(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c) internal pure returns (uint256) {
        return y0 + px * 1e18 / py * (c * (2 * x0 - xt) / 1e18 + (1e18 - c) * x0 / 1e18 * x0 / xt - x0) / 1e18;
    }

    /// @inheritdoc IMaglev
    function verify(uint256 newReserve0, uint256 newReserve1) public view returns (bool) {
        if (newReserve0 >= initialReserve0) {
            if (newReserve1 >= initialReserve1) return true;
            return newReserve0 >= f(newReserve1, priceY, priceX, initialReserve1, initialReserve0, concentrationY);
        } else {
            if (newReserve1 < initialReserve1) return false;
            return newReserve1 >= f(newReserve0, priceX, priceY, initialReserve0, initialReserve1, concentrationX);
        }
    }

    /// @inheritdoc IMaglev
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
        if (amount0In > 0) {
            depositAssets(vault0, amount0In);
            amount0In = amount0In * feeMultiplier / 1e18;
        }

        uint256 amount1In = IERC20(asset1).balanceOf(address(this));
        if (amount1In > 0) {
            depositAssets(vault1, amount1In);
            amount1In = amount1In * feeMultiplier / 1e18;
        }

        // Verify curve invariant is satisified

        {
            uint256 newReserve0 = reserve0 + amount0In - amount0Out;
            uint256 newReserve1 = reserve1 + amount1In - amount1Out;

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, Overflow());
            require(verify(newReserve0, newReserve1), CurveViolation());

            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);

            emit Swap(
                msg.sender, amount0In, amount1In, amount0Out, amount1Out, uint112(newReserve0), uint112(newReserve1), to
            );
        }
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, status);
    }

    // Internal utilities

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

            if (myDebt(vault) == 0) {
                IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }
    }
}
