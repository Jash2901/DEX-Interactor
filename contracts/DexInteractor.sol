// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Core & periphery imports (make sure these packages are installed)
// The exact pathing matches the Uniswap v4 repo layout; if you use Hardhat/Foundry ensure remappings are correct.
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "@uniswap/v4-core/src/types/PoolKey.sol";
import "@uniswap/v4-core/src/types/PoolId.sol";
import "@uniswap/v4-core/src/types/PoolOperation.sol";
import "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolOperation as LocalPoolOperation} from "../types/PoolOperation.sol";

interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

/// @title DexInteractor
/// @notice Small teaching-oriented integrator for Uniswap v4. Implements:
///         - unlockCallback (the v4 callback)
///         - user-facing helpers: swapExactInput, addLiquidity, removeLiquidity
///         - quoter & state view read helpers
///
/// @dev This contract demonstrates the unlock -> callback -> settle flow.
///     You must supply correct PoolKey / PoolId values and appropriate token approvals in tests.
contract DexInteractor is IUnlockCallback {
    IPoolManager public poolManager;
    IV4Quoter public quoter;
    IStateView public stateView;

    // Events for visibility in tests
    event CallbackInvoked(address caller, uint8 action);
    event SwapInitiated();
    event LiquidityInitiated();

    // Action codes used in the callback wrapper encoding
    uint8 private constant ACTION_SWAP = 0;
    uint8 private constant ACTION_MODIFY_LIQUIDITY = 1;

    constructor(address _poolManager, address _quoter, address _stateView) {
        require(_poolManager != address(0), "poolManager required");
        poolManager = IPoolManager(_poolManager);
        quoter = IV4Quoter(_quoter);
        stateView = IStateView(_stateView);
    }

    // ======================================================
    // High-level user-facing functions (Step 6)
    // ======================================================

    /// @notice Simple helper to swap an exact input amount.
    /// @dev This is a convenience wrapper that builds a SwapParams struct and calls `poolManager.unlock`.
    ///      For production you might want a richer wrapper, slippage handling, and safe approvals.
    ///
    /// @param key The PoolKey identifying the pool to swap in (token currencies, fee, tickSpacing, hooks).
    /// @param amountIn Exact input amount (uint128 recommended).
    /// @param zeroForOne Direction: true = currency0 -> currency1, false = currency1 -> currency0
    /// @param sqrtPriceLimitX96 Price limit for the swap (use 0 for no special limit; but check docs).
    /// @param hookData Arbitrary hookData bytes forwarded to any hooks the pool uses.
    function swapExactInput(
        PoolKey memory key,
        uint128 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96,
        bytes calldata hookData
    ) external {
        // Build the low-level SwapParams struct used by PoolManager.swap
        // NOTE: The exact type of PoolOperation.SwapParams is defined in Uniswap v4 core types.
        PoolOperation.SwapParams memory params = PoolOperation.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(uint256(amountIn)), // exact input -> positive amountSpecified (signed in v4)
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            tickSpacing: key.tickSpacing, // preserve tickSpacing here (per v4 types)
            // lpFeeOverride is optional in some interfaces; PoolOperation type may include it. If your version differs adjust.
            lpFeeOverride: uint24(0)
        });

        // Encode the action + payload and unlock the PoolManager -> callback will be invoked
        bytes memory payload = abi.encode(key, params, hookData);
        bytes memory data = abi.encode(uint8(ACTION_SWAP), payload);

        // Caller must have approved tokens / transferred funds into this integrator per your test flow.
        poolManager.unlock(data);

        emit SwapInitiated();
    }

    /// @notice Add liquidity (or remove if liquidityDelta negative) helper.
    /// @dev liquidityDelta is an int128 in the core structs; positive = add, negative = remove.
    ///
    /// @param key PoolKey identifying the pool.
    /// @param params Low-level ModifyLiquidityParams (owner, tickLower, tickUpper, liquidityDelta, tickSpacing, salt).
    /// @param hookData Arbitrary bytes forwarded to hooks.
    function modifyLiquidity(
        PoolKey memory key,
        LocalPoolOperation.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external {
        // Copy memory struct before encoding
        LocalPoolOperation.ModifyLiquidityParams memory paramsMem = params;
        bytes memory payload = abi.encode(key, paramsMem, hookData);
        bytes memory data = abi.encode(uint8(ACTION_MODIFY_LIQUIDITY), payload);

        poolManager.unlock(data);

        emit LiquidityInitiated();
    }

    /// @notice removeLiquidity convenience wrapper (calls modifyLiquidity with negative liquidityDelta)
    /// @dev For clarity this example accepts the full ModifyLiquidityParams where liquidityDelta should be negative.
    function removeLiquidity(
        PoolKey memory key,
        LocalPoolOperation.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external {
        // As above, the params.liquidityDelta should be negative for removal.
        bytes memory payload = abi.encode(key, params, hookData);
        bytes memory data = abi.encode(uint8(ACTION_MODIFY_LIQUIDITY), payload);

        poolManager.unlock(data);

        emit LiquidityInitiated();
    }

    // ======================================================
    // Read-only helpers (no lock needed)
    // ======================================================

    /// @notice Quote how much output you'd get for exact input on a single pool
    /// @dev This calls the on-chain quoter. The quoter is not gas efficient and is intended for off-chain use,
    ///      but this function demonstrates how to call it from a contract/test.
    function getQuoteSingle(
        IV4Quoter.QuoteExactSingleParams calldata params
    ) external returns (uint256 amountOut, uint256 gasEstimate) {
        // The quoter returns (amountOut, gasEstimate)
        (amountOut, gasEstimate) = quoter.quoteExactInputSingle(params);
        return (amountOut, gasEstimate);
    }

    /// @notice Get basic pool slot0 state (price, tick, fees)
    /// @param poolId The PoolId for the pool (obtainable via PoolKey.toId offchain or via helper libs)
    function getPoolSlot0(PoolId memory poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        return stateView.getSlot0(poolId);
    }

    /// @notice Get pool liquidity (total)
    function getPoolLiquidity(PoolId memory poolId) external view returns (uint128 liquidity) {
        return stateView.getLiquidity(poolId);
    }

    // ======================================================
    // unlockCallback - called by PoolManager during unlock
    // ======================================================
    ///
    /// The callback decodes the `action` wrapper and calls the appropriate PoolManager method.
    /// After performing operations, it calls `poolManager.settle()` to settle tokens/deltas.
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager can call");

        // decode wrapper (uint8 action, bytes payload)
        (uint8 action, bytes memory payload) = abi.decode(data, (uint8, bytes));

        emit CallbackInvoked(msg.sender, action);

        if (action == ACTION_SWAP) {
            // decode and call swap
            (PoolKey memory key, PoolOperation.SwapParams memory params, bytes memory hookData) =
                abi.decode(payload, (PoolKey, PoolOperation.SwapParams, bytes));

            // Execute the swap on PoolManager while it's unlocked
            PoolOperation.BalanceDelta memory delta = poolManager.swap(key, params, hookData);

            // After performing the swap operation, settle any deltas (pulls tokens into reserves or credits)
            poolManager.settle();

            return "";
        } else if (action == ACTION_MODIFY_LIQUIDITY) {
            // decode and call modifyLiquidity (add/remove)
            (PoolKey memory key, LocalPoolOperation.ModifyLiquidityParams memory params, bytes memory hookData) =
                abi.decode(payload, (PoolKey, LocalPoolOperation.ModifyLiquidityParams, bytes));

            (PoolOperation.BalanceDelta memory callerDelta, PoolOperation.BalanceDelta memory feesAccrued) =
                poolManager.modifyLiquidity(key, params, hookData);

            // Settle any deltas created by modifyLiquidity
            poolManager.settle();

            return "";
        } else {
            revert("Unknown action");
        }
    }
}
