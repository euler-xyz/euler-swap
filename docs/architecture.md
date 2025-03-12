# EulerSwap architecture

## Overview

EulerSwap is an automated market maker (AMM) that integrates with Euler credit vaults to provide deeper liquidity for swaps.

Each EulerSwap instance is a lightweight smart contract that functions as an [EVC operator](https://evc.wtf/docs/whitepaper/#operators) while implementing a highly customizable AMM curve to determine swap output amounts.

When a user initiates a swap, the EulerSwap operator borrows the required output token using the input token as collateral. The operator’s internal AMM curve governs the exchange rate, ensuring deep liquidity over short timeframes while maintaining a balance between collateral and debt over the long term.

## Code structure

EulerSwap’s code is split into two main smart contracts:

### EulerSwap core (`EulerSwap.sol`)

- Handles collateralization via EVC and Euler credit vaults.
- Implements AMM curve invariant checks through the `verify()` function.

### EulerSwap periphery (`EulerSwapPeriphery.sol`)

- Provides simplified functions for retrieving swap quotes from the AMM curve.
- Acts as a convenience layer for external integrations.

## Operational flow

The following steps outline how an EulerSwap operator is created and configured:

1. Deposit initial liquidity into one or both of the underlying credit vaults to enable swaps.
2. Deploy an instance of EulerSwap, specifying AMM curve parameters and the `fee`.
3. Set the [virtual reserves](#virtual-reserves) by invoking `setVirtualReserves()`.
4. Install the EulerSwap contract as an operator for the user's account.
5. Invoke the `configure()` function on the EulerSwap contract.

Once configured, the EulerSwap contract can process swaps. When a user invokes `swap()`, the contract facilitates borrowing and transfers between the underlying vaults as dictated by the AMM curve.

### Virtual reserves

The initial deposits in the vaults provide starting liquidity and facilitate swaps. In traditional AMMs like Uniswap, these balances are known as _reserves_.
However, relying solely on these assets would impose a hard limit on swap size. To overcome this, EulerSwap introduces _virtual reserves_, allowing the AMM to extend its effective liquidity by borrowing against its real reserves.

Virtual reserves control the maximum debt that the EulerSwap contract will attempt to acquire on each of its two vaults. Each vault can be configured independently. For example, if the initial investment has a NAV of \$1000, and virtual reserves are configured at \$5000 for each vault, then the maximum LTV loan that the AMM will support will be `5000/6000 = 0.8333`. In order to leave a safety buffer, it is recommended to select a maximum LTV that is below the borrowing LTV of the vault. Note that it depends on the [curve](#curves) if the maximum LTV can actually be achieved. A constant product curve will only approach these reserve levels asymptotically, since each unit will get more and more expensive. However, with a constant sum curve, the maximum LTV can be achieved directly.

### Reserve synchronisation

The EulerSwap contract tracks what it believes the reserves to be by caching their values in storage. These reserves are updated on each swap. However, since the balance is not actually held by the EulerSwap contract (it is simply an operator), the actual underlying balances may get out of sync. This can happen gradually as interest is accrued, or suddenly if the holder moves funds or the position is liquidated. When this occurs, the `syncVirtualReserves()` should be invoked. This determines the actual balances (and debts) of the holder and adjusts them by the configured virtual reserve levels.

## Components

### **1. Core contracts**

#### **EulerSwap contract**

The `EulerSwap` contract is the core of EulerSwap and is responsible for:

- Managing liquidity reserves.
- Executing token swaps based on the EulerSwap curve.
- Enforcing collateralization through EVC.
- Maintaining vault and asset associations.

##### **Key features**

- Implements a unique **swapping curve** that ensures efficient liquidity provision.
- Handles **collateralized borrowing** via vaults.
- Enforces a **fee multiplier** to apply swap fees.
- Implements a **non-reentrant mechanism** to prevent recursive calls.

##### **Key functions**

- `activate()`: Initializes vault approvals and enables collateral.
- `swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)`: Performs asset swaps and enforces curve constraints.
- `verify(uint256 newReserve0, uint256 newReserve1)`: Ensures reserves conform to the defined curve.
- `f(uint256 xt, uint256 px, uint256 py, uint256 x0, uint256 y0, uint256 c)`: Defines the EulerSwap curve formula for swaps.

### **2. Periphery contracts**

#### **EulerSwapPeriphery contract**

The `EulerSwapPeriphery` contract extends the functionality of the core EulerSwap contract by providing:

- **Swap price quotations** before execution.
- **Liquidity checks** to ensure solvency before transactions.
- **Binary search mechanisms** for dynamic price calculation.

##### **Key functions**

- `quoteExactInput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountIn)`: Estimates the output amount for a given input.
- `quoteExactOutput(address eulerSwap, address tokenIn, address tokenOut, uint256 amountOut)`: Estimates the required input amount to receive a specified output.
- `computeQuote(IEulerSwap eulerSwap, address tokenIn, address tokenOut, uint256 amount, bool exactIn)`: A high-level function to compute swaps while enforcing fee multipliers.
- `binarySearch(IEulerSwap eulerSwap, uint112 reserve0, uint112 reserve1, uint256 amount, bool exactIn, bool asset0IsInput)`: Uses binary search to determine an optimal swap amount along the curve.

### **3. Vault integration**

EulerSwap integrates with **Ethereum Vault Connector (EVC)** to enable collateralized trading. Each liquidity vault manages asset balances, borrowing, and repayment, ensuring:

- **Controlled debt exposure**
- **Dynamic liquidity reserves**
- **Secure vault interactions**

### **4. Security mechanisms**

- **Non-reentrant protection**: Ensures swaps do not trigger recursive calls.
- **Collateral verification**: Uses EVC to verify and adjust collateral balances.
- **Curve constraints enforcement**: Prevents swap execution that violates the defined curve invariant.
- **Precision safeguards**: Fixed-point arithmetic (`1e18` scaling) ensures precision in calculations.

## Summary

EulerSwap’s architecture is designed for **efficient, secure, and collateral-backed trading** with a custom **swapping curve**. The system leverages:

- **EulerSwap** as the core AMM contract.
- **EulerSwapPeriphery** for auxiliary quoting and validations.
- **Ethereum Vault Connector (EVC)** for collateralized vault management.
- **Security-focused design** to prevent vulnerabilities in asset handling.

This modular and scalable architecture ensures that EulerSwap provides robust DeFi trading functionality while maintaining security and efficiency.
