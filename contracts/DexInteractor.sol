// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Uniswap v4 imports
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "@uniswap/v4-core/src/types/PoolKey.sol";
import "@uniswap/v4-core/src/types/PoolId.sol";
import "@uniswap/v4-core/src/types/PoolOperation.sol";
import "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Callback interface used by PoolManager during unlock
interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

/// @notice DexInteractor: wrapper to interact with Uniswap v4 via PoolManager
contract DexInteractor is IUnlockCallback {
    IPoolManager public poolManager;
    IV4Quoter public quoter;
    IStateView public stateView;

    // Action codes for callback decoding
    uint8 private constant ACTION_SWAP = 0;
    uint8 private constant ACTION_MODIFY_LIQUIDITY = 1;

    constructor(address _poolManager, address _quoter, address _stateView) {
        require(_poolManager != address(0), "poolManager required");
        poolManager = IPoolManager(_poolManager);
        quoter = IV4Quoter(_quoter);
        stateView = IStateView(_stateView);
    }

    // ======================================================
    // Step 6: User-facing functions
    // ======================================================

    /// @notice Swap tokens (exact input)
    function swapExactInput(
        PoolKey calldata key,
        PoolOperation.SwapParams calldata params,
        bytes calldata hookData
    ) external {
        // Approve the input token to PoolManager
        _approveToken(params.zeroForOne ? key.currency0 : key.currency1, params.amountSpecified);

        // Encode action data
        bytes memory payload = abi.encode(key, params, hookData);
        bytes memory data = abi.encode(ACTION_SWAP, payload);

        // Call PoolManager.lock -> triggers unlockCallback
        poolManager.lock(data);
    }

    /// @notice Add/remove liquidity
    function modifyLiquidity(
        PoolKey calldata key,
        PoolOperation.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external {
        // If adding liquidity, approve tokens
        if (params.liquidityDelta > 0) {
            _approveToken(key.currency0, uint256(params.liquidityDelta));
            _approveToken(key.currency1, uint256(params.liquidityDelta));
        }

        // Encode action data
        bytes memory payload = abi.encode(key, params, hookData);
        bytes memory data = abi.encode(ACTION_MODIFY_LIQUIDITY, payload);

        poolManager.lock(data);
    }

    /// @notice Quote swap output
    function getQuote(
        PoolKey calldata key,
        PoolOperation.SwapParams calldata params
    ) external returns (uint256 amountOut) {
        (amountOut,) = quoter.quote(key, params);
    }

    /// @notice Get pool state
    function getPoolState(PoolKey calldata key)
        external
        view
        returns (IStateView.PoolState memory state)
    {
        state = stateView.getPoolState(key);
    }

    // ======================================================
    // Step 7: unlockCallback with proper settlement
    // ======================================================
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager can call");

        (uint8 action, bytes memory payload) = abi.decode(data, (uint8, bytes));

        if (action == ACTION_SWAP) {
            (PoolKey memory key, PoolOperation.SwapParams memory params, bytes memory hookData) =
                abi.decode(payload, (PoolKey, PoolOperation.SwapParams, bytes));

            // Perform swap
            (CurrencyDelta[] memory deltas,) = poolManager.swap(key, params, hookData);

            // Settle token deltas
            _settleDeltas(deltas);

        } else if (action == ACTION_MODIFY_LIQUIDITY) {
            (PoolKey memory key, PoolOperation.ModifyLiquidityParams memory params, bytes memory hookData) =
                abi.decode(payload, (PoolKey, PoolOperation.ModifyLiquidityParams, bytes));

            // Add/remove liquidity
            (CurrencyDelta[] memory deltas,) = poolManager.modifyLiquidity(key, params, hookData);

            // Settle token deltas
            _settleDeltas(deltas);

        } else {
            revert("Unknown action");
        }

        return "";
    }

    // ======================================================
    // Step 8: Helper functions
    // ======================================================

    /// @notice Approve token to be used by PoolManager
    function _approveToken(address token, uint256 amount) internal {
        IERC20(token).approve(address(poolManager), amount);
    }

    /// @notice Build a PoolKey struct easily
    function buildPoolKey(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) external pure returns (PoolKey memory key) {
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks
        });
    }

    /// @notice Internal utility to settle token deltas correctly
    function _settleDeltas(CurrencyDelta[] memory deltas) internal {
        for (uint256 i = 0; i < deltas.length; i++) {
            CurrencyDelta memory delta = deltas[i];
            if (delta.amount < 0) {
                // We owe tokens to the PoolManager → settle
                uint256 amountToPay = uint256(-delta.amount);
                IERC20(delta.currency).transfer(address(poolManager), amountToPay);
                poolManager.settle(delta.currency, amountToPay);
            } else if (delta.amount > 0) {
                // PoolManager owes us tokens → take
                uint256 amountToReceive = uint256(delta.amount);
                poolManager.take(delta.currency, amountToReceive, msg.sender);
            }
        }
    }

    /// @notice Utility to manually settle any outstanding deltas (if needed)
    function settleNow(address token, uint256 amount) external {
        IERC20(token).transfer(address(poolManager), amount);
        poolManager.settle(token, amount);
    }
}
