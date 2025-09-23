// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Uniswap v4 imports
import "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
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

    // 4 function: swapExactInputSingle, swapExactInput, swapExactOutputSingle, swapExactOutput

    /// @notice Swap tokens (exact input)
    function swapExactInput(
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external {
        address inputToken = params.zeroForOne ? key.currency0 : key.currency1;

        // Approve PoolManager to pull tokens
        IERC20(inputToken).approve(address(poolManager), params.amountSpecified);

        // Lock the pool and perform swap (Uniswap handles settlement)
        poolManager.unlock(
            abi.encode(uint8(0), abi.encode(key, params, hookData))
        );
    }
}