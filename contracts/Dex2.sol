// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract Interactor{
    IPoolManager public poolManager;

    constructor(address _poolManager){
        poolManager = IPoolManager(_poolManager);
    }

    function swapExactInputSingle (
    PoolKey memory poolKey,
    bool zeroForOne,
    uint128 amountIn,
    uint128 amountOutMinimum
    ) external returns (uint128 amountOut) {
        if (amountIn == ActionConstants.OPEN_DELTA) {
            revert("OPEN_DELTA not supported");
        }

        int256 amountSpecified = -int256(uint256(amountIn));
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        BalanceDelta delta = poolManager.swap(poolKey, params, bytes(""));
        amountOut = uint128(
            zeroForOne 
                ? -BalanceDeltaLibrary.amount1(delta) 
                : -BalanceDeltaLibrary.amount0(delta)
        );

        require(amountOut >= amountOutMinimum, "Too little received");
    }

}