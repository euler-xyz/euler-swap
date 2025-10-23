// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IEulerSwap {
    /// @dev Constant pool parameters, loaded from trailing calldata.
    struct StaticParams {
        address supplyVault0;
        address supplyVault1;
        address borrowVault0;
        address borrowVault1;
        address eulerAccount;
        address feeRecipient;
    }

    /// @dev Reconfigurable pool parameters, loaded from storage.
    struct DynamicParams {
        uint112 equilibriumReserve0;
        uint112 equilibriumReserve1;
        uint112 minReserve0;
        uint112 minReserve1;
        uint80 priceX;
        uint80 priceY;
        uint64 concentrationX;
        uint64 concentrationY;
        uint64 fee0;
        uint64 fee1;
        uint40 expiration;
        uint8 swapHookedOperations;
        address swapHook;
    }

    /// @dev Starting configuration of pool storage.
    struct InitialState {
        uint112 reserve0;
        uint112 reserve1;
    }

    /// @notice Performs initial activation setup, such as approving vaults to access the
    /// EulerSwap instance's tokens, enabling vaults as collateral, setting up Uniswap
    /// hooks, etc. This should only be invoked by the factory.
    function activate(DynamicParams calldata dynamicParams, InitialState calldata initialState) external;

    /// @notice Installs or uninstalls a manager. Managers can reconfigure the dynamic EulerSwap parameters.
    /// Only callable by the owner (eulerAccount).
    /// @param manager Address to install/uninstall
    /// @param installed Whether the manager should be installed or uninstalled
    function setManager(address manager, bool installed) external;

    /// @notice Addresses configured as managers. Managers can reconfigure the pool parameters.
    /// @param manager Address to check
    /// @return installed Whether the address is currently a manager of this pool
    function managers(address manager) external view returns (bool installed);

    /// @notice Reconfigured the pool's parameters. Only callable by the owner (eulerAccount)
    /// or a manager.
    function reconfigure(DynamicParams calldata dParams, InitialState calldata initialState) external;

    /// @notice Retrieves the pool's static parameters.
    function getStaticParams() external view returns (StaticParams memory);

    /// @notice Retrieves the pool's dynamic parameters.
    function getDynamicParams() external view returns (DynamicParams memory);

    /// @notice Retrieves the underlying assets supported by this pool.
    function getAssets() external view returns (address asset0, address asset1);

    /// @notice Retrieves the current reserves from storage, along with the pool's lock status.
    /// @return reserve0 The amount of asset0 in the pool
    /// @return reserve1 The amount of asset1 in the pool
    /// @return status The status of the pool (0 = unactivated, 1 = unlocked, 2 = locked)
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 status);

    /// @notice Whether or not this EulerSwap instance is installed as an operator of
    /// the eulerAccount in the EVC.
    function isInstalled() external view returns (bool installed);

    /// @notice Generates a quote for how much a given size swap will cost.
    /// @param tokenIn The input token that the swapper SENDS
    /// @param tokenOut The output token that the swapper GETS
    /// @param amount The quantity of input or output tokens, for exact input and exact output swaps respectively
    /// @param exactIn True if this is an exact input swap, false if exact output
    /// @return The quoted quantity of output or input tokens, for exact input and exact output swaps respectively
    function computeQuote(address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        external
        view
        returns (uint256);

    /// @notice Upper-bounds on the amounts of each token that this pool can currently support swaps for.
    /// @return limitIn Max amount of `tokenIn` that can be sold.
    /// @return limitOut Max amount of `tokenOut` that can be bought.
    function getLimits(address tokenIn, address tokenOut) external view returns (uint256 limitIn, uint256 limitOut);

    /// @notice Optimistically sends the requested amounts of tokens to the `to`
    /// address, invokes `eulerSwapCall` callback on `to` (if `data` was provided),
    /// and then verifies that a sufficient amount of tokens were transferred to
    /// satisfy the swapping curve invariant.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
