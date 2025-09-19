// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Uniswap v4 imports
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "@uniswap/v4-core/src/types/PoolKey.sol";
import "@uniswap/v4-core/src/types/PoolOperation.sol";
import "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice DexInteractor: wrapper to interact with Uniswap v4 via PoolManager
contract DexInteractor {
    using SafeERC20 for IERC20;

    IPoolManager public immutable poolManager;
    IV4Quoter public immutable quoter;
    IStateView public immutable stateView;

    constructor(address _poolManager, address _quoter, address _stateView) {
        require(_poolManager != address(0), "poolManager required");
        poolManager = IPoolManager(_poolManager);
        quoter = IV4Quoter(_quoter);
        stateView = IStateView(_stateView);
    }

    /// @notice Swap tokens (exact input)
    function swapExactInput(
        PoolKey calldata key,
        PoolOperation.SwapParams calldata params,
        bytes calldata hookData
    ) external {
        address inputToken = params.zeroForOne ? key.currency0 : key.currency1;

        // Approve PoolManager to pull tokens
        IERC20(inputToken).safeApprove(address(poolManager), params.amountSpecified);

        // Lock the pool and perform swap (Uniswap handles settlement)
        poolManager.lock(
            abi.encode(uint8(0), abi.encode(key, params, hookData))
        );
    }

    /// @notice Add/remove liquidity
    function modifyLiquidity(
        PoolKey calldata key,
        PoolOperation.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external {
        if (params.liquidityDelta > 0) {
            IERC20(key.currency0).safeApprove(address(poolManager), uint256(params.liquidityDelta));
            IERC20(key.currency1).safeApprove(address(poolManager), uint256(params.liquidityDelta));
        }

        poolManager.lock(
            abi.encode(uint8(1), abi.encode(key, params, hookData))
        );
    }

    /// @notice Quote swap output (no funds involved)
    function getQuote(
        PoolKey calldata key,
        PoolOperation.SwapParams calldata params
    ) external returns (uint256 amountOut) {
        (amountOut,) = quoter.quote(key, params);
    }

    /// @notice Get pool state (reserves, liquidity, tick)
    function getPoolState(PoolKey calldata key)
        external
        view
        returns (IStateView.PoolState memory state)
    {
        state = stateView.getPoolState(key);
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
}
