# Mini Uniswap V2

一个使用 Solidity + Foundry 从零实现的 Uniswap V2 简化版本，包含 Factory、Pair、Router、Library、LP Token、CREATE2 地址预测、AMM swap、add/remove liquidity 等核心逻辑。

## Features
- Factory: token pair creation with CREATE2
- Pair: mint/burn/swap/sync/skim
- Router: addLiquidity, removeLiquidity, swapExactTokensForTokens
- Pricing: x * y = k, 0.3% swap fee
- Testing: unit tests, fuzz tests, invariant tests

## Architecture
放一张图：User -> Router -> Pair -> ERC20

## Core Mechanisms
### 1. CREATE2 deterministic pair address
### 2. LP minting and MINIMUM_LIQUIDITY
### 3. Swap invariant check
### 4. Router slippage and deadline protection

## Test Report
| Module | Test Type | Covered Cases |
|---|---|---|
| Factory | Unit/Fuzz | sort tokens, duplicate pair, zero address |
| Pair | Unit/Invariant | mint, burn, swap, k invariant |
| Router | Integration | add/remove liquidity, swap path |

## How to Run
forge install
forge build
forge test -vvv
forge coverage

## Known Limitations
- Not production-ready
- Does not support fee-on-transfer tokens
- Oracle/TWAP only simplified
- No formal audit