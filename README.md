🚀 Roadmap for Building Your Uniswap v4 Interactor Contract

**Step 1: Understand the Goal**
- Build a smart contract (DexInteractor.sol) that can:
  - Swap tokens using Uniswap v4.
  - Add/remove liquidity to a pool.
  - Get swap quotes.
  - Read pool state (reserves, price, liquidity, tick).
- All interactions use Uniswap v4's lock + callback mechanism via PoolManager.

**Step 2: Set Up the Environment**
- Use Hardhat for development.
- Install Uniswap v4 contracts:
  ```
  npm install @uniswap/v4-core @uniswap/v4-periphery
  ```
- Prepare mock ERC20 tokens or testnet tokens (WETH, USDC, etc.).

**Step 3: Import the Right Interfaces**
- In your contract, import:
  - `IPoolManager` (core pool interactions)
  - `IUnlockCallback` (for callback logic)
  - `IV4Quoter` (swap quotes)
  - `IStateView` (pool state)
  - ERC20 interfaces

**Step 4: Write the Contract Skeleton**
- Create `DexInteractor` contract.
- Store:
  - PoolManager address
  - Quoter address
  - StateView address
  - Token addresses (WETH, USDC, etc.)
- Constructor: initialize these addresses.

**Step 5: Implement the Lock/Callback Mechanism**
- Uniswap v4 uses a lock/callback pattern for state-changing actions:
  - Call `PoolManager.lock(data)` to initiate.
  - PoolManager calls your contract's `unlockCallback(bytes calldata data)`.
  - Inside `unlockCallback`, decode the action (swap, add/remove liquidity).
  - Call the appropriate PoolManager function (`swap`, `modifyLiquidity`, etc.).
  - Settle token deltas using `settle` and `take`.

**Step 6: Write User-Facing Functions**
- Functions users will call:
  - `swapExactInput(uint256 amountIn, address tokenIn, address tokenOut)`
    - Encodes swap request, calls `lock`.
  - `addLiquidity(...)`
    - Encodes liquidity params, calls `lock`.
  - `removeLiquidity(...)`
    - Encodes removal params, calls `lock`.
  - `getQuote(...)`
    - Calls Quoter directly (no lock needed).
  - `getPoolState(...)`
    - Calls StateView directly (no lock needed).

**Step 7: Handle Token Settlement**
- After swap/liquidity change, PoolManager tracks token deltas.
- In your callback:
  - Use `settle(token, amount)` to pay tokens to PoolManager.
  - Use `take(token, amount)` to withdraw owed tokens.
- All deltas must be settled before lock is released.

**Step 8: Write Helper Functions**
- `buildPoolKey()` — creates a PoolKey struct (token0, token1, fee, tickSpacing).
- `settleDeltas()` — loops through deltas and calls `settle`/`take`.

**Step 9: Testing**
- Write Hardhat tests:
  - Deploy mock tokens.
  - Deploy PoolManager (or use testnet).
  - Deploy DexInteractor.
  - Mint tokens to your wallet.
  - Approve DexInteractor to use your tokens.
  - Test:
    - `getQuote` — print expected output.
    - `swapExactInput` — check balances before/after.
    - `addLiquidity` — confirm liquidity position.
    - `getPoolState` — confirm reserves.

**Step 10: Deliverables for Internship**
- A Solidity contract: DexInteractor.sol.
- A test script (Hardhat/Foundry) showing swap, add liquidity, get reserves.
- A README explaining how to deploy and run.
- Demonstrate full Uniswap v4 interaction via PoolManager's lock/callback pattern.
