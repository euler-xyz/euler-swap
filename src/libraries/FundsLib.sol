// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";

import {IEulerSwap} from "../interfaces/IEulerSwap.sol";

library FundsLib {
    using SafeERC20 for IERC20;

    error DepositFailure(bytes reason);

    error E_ZeroShares(); // EVK error
    error ZeroShares(); // Euler Earn error

    /// @notice Approves tokens for a given vault, supporting both standard approvals and permit2
    /// @param vault The address of the vault to approve the token for
    function approveVault(address vault) internal {
        address asset = IEVault(vault).asset();
        address permit2 = IEVault(vault).permit2Address();
        if (permit2 == address(0)) {
            IERC20(asset).forceApprove(vault, type(uint256).max);
        } else {
            IERC20(asset).forceApprove(permit2, type(uint256).max);
            IAllowanceTransfer(permit2).approve(asset, vault, type(uint160).max, type(uint48).max);
        }
    }

    /// @notice Withdraws assets from a vault, first using available balance and then borrowing if needed
    /// @param evc EVC instance
    /// @param eulerAccount Euler account to withdraw/borrow on behalf of
    /// @param supplyVault The address of the vault to withdraw from
    /// @param borrowVault The address of the vault to borrow from
    /// @param amount The total amount of assets to withdraw
    /// @param to The address that will receive the withdrawn assets
    /// @dev This function first checks if there's an existing balance in the vault.
    /// @dev If there is, it withdraws the minimum of the requested amount and available balance.
    /// @dev If more assets are needed after withdrawal, it enables the controller and borrows the remaining amount.
    function withdrawAssets(
        address evc,
        address eulerAccount,
        address supplyVault,
        address borrowVault,
        uint256 amount,
        address to
    ) internal {
        uint256 balance;
        {
            uint256 shares = IEVault(supplyVault).balanceOf(eulerAccount);
            balance = shares == 0 ? 0 : IEVault(supplyVault).convertToAssets(shares);
        }

        if (balance > 0) {
            uint256 avail = amount < balance ? amount : balance;
            IEVC(evc).call(supplyVault, eulerAccount, 0, abi.encodeCall(IERC4626.withdraw, (avail, to, eulerAccount)));
            amount -= avail;
        }

        if (amount > 0) {
            IEVC(evc).enableController(eulerAccount, borrowVault);
            IEVC(evc).call(borrowVault, eulerAccount, 0, abi.encodeCall(IBorrowing.borrow, (amount, to)));
        }
    }

    /// @notice Deposits assets into a vault and automatically repays any outstanding debt
    /// @param evc EVC instance
    /// @param eulerAccount Euler account to repay/deposit on behalf of
    /// @param supplyVault The address of the vault to deposit to
    /// @param borrowVault The address of the vault to repay to
    /// @param amount The total amount to deposit
    /// @return The amount of assets successfully deposited (may be less than requested)
    /// @dev This function attempts to deposit assets into the specified vault.
    /// @dev If the deposit fails with E_ZeroShares error, it safely returns 0 (this happens with very small amounts).
    /// @dev After successful deposit, if the user has any outstanding controller-enabled debt, it attempts to repay it.
    /// @dev If all debt is repaid, the controller is automatically disabled to reduce gas costs in future operations.
    function depositAssets(address evc, address eulerAccount, address supplyVault, address borrowVault, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 deposited;

        if (IEVC(evc).isControllerEnabled(eulerAccount, borrowVault)) {
            uint256 debt = IEVault(borrowVault).debtOf(eulerAccount);
            uint256 repaid = IEVault(borrowVault).repay(amount > debt ? debt : amount, eulerAccount);

            amount -= repaid;
            debt -= repaid;
            deposited += repaid;

            if (debt == 0) {
                IEVC(evc).call(borrowVault, eulerAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }

        if (amount > 0) {
            try IEVault(supplyVault).deposit(amount, eulerAccount) {}
            catch (bytes memory reason) {
                require(
                    bytes4(reason) == E_ZeroShares.selector || bytes4(reason) == ZeroShares.selector,
                    DepositFailure(reason)
                );
                amount = 0;
            }

            deposited += amount;
        }

        return deposited;
    }
}
