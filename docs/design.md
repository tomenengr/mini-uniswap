# 设计说明

Mini Uniswap V2 是一个学习型 Uniswap V2 风格 AMM。目标不是完整复制生产协议，而是把核心机制写清楚、测清楚：CREATE2 Pair 部署、LP mint/burn、恒定乘积 swap、reserve 记账、Router 用户入口、flash swap、protocol fee 和基础 TWAP。

## 架构

| 层级 | 合约 | 职责 |
| --- | --- | --- |
| Factory | `Factory.sol` | 排序 token，使用 CREATE2 创建唯一 Pair，维护 `getPair` 和 `feeTo` |
| Pair | `Pair.sol` | 持有池子资产，维护 reserves，铸造/销毁 LP，执行 swap 和 K 值校验 |
| Router | `Router.sol` | 用户入口，封装加减流动性、swap、滑点、deadline 和 ETH/WETH 路径 |
| Library | `Library.sol` | Pair 地址预测、reserve 查询、quote、amount in/out 和 path 计算 |
| Oracle | `SimpleTwapOracle.sol` | 消费 Pair 累计价格，计算固定窗口 TWAP 报价 |

典型调用路径：

```text
User -> Router -> Factory / Pair -> ERC20 tokens
Oracle -> Pair
```

Router 负责用户体验和参数检查；Pair 是资金池状态和安全约束的最终来源。

## 核心机制

### CREATE2 Pair

Factory 对 token 地址排序后，用 `keccak256(token0, token1)` 作为 salt 创建 Pair。`Library.pairFor` 使用相同公式预测地址，因此 Router 可以在不额外读取 `getPair` 的情况下定位 Pair。

### Reserve 与 Balance

Pair 同时依赖两类数据：

- `balanceOf(pair)`：ERC20 合约中的真实余额。
- `reserve0/reserve1`：Pair 上一次 `_update` 后记录的账面库存。

`mint`、`burn`、`swap`、`sync` 都会在完成计算和校验后调用 `_update`。`skim` 用于转出 balance 超过 reserve 的多余部分。

### LP mint / burn

首次添加流动性：

```text
liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
```

后续添加流动性：

```text
liquidity = min(amount0 * totalSupply / reserve0, amount1 * totalSupply / reserve1)
```

移除流动性：

```text
amount0 = liquidity * balance0 / totalSupply
amount1 = liquidity * balance1 / totalSupply
```

`MINIMUM_LIQUIDITY` 永久铸造给 `address(0)`，避免第一个 LP 完全移除池子份额。

### Swap 与 K 值约束

exact input 输出公式：

```text
amountInWithFee = amountIn * 997
amountOut = amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee)
```

exact output 输入公式：

```text
amountIn = reserveIn * amountOut * 1000 / ((reserveOut - amountOut) * 997) + 1
```

Pair 在转出 token 和可选 callback 后读取实际余额，反推出 `amount0In/amount1In`，再执行带 0.3% fee 的 K 值校验：

```text
(balance0 * 1000 - amount0In * 3)
  * (balance1 * 1000 - amount1In * 3)
  >= reserve0 * reserve1 * 1000^2
```

flash swap 也依赖这个模式：callback 可以先拿到 token，但交易结束前必须还回足够资产，否则 K 校验失败。

### Protocol Fee

当 `Factory.feeTo()` 非零时，Pair 在 `mint` / `burn` 中执行 `_mintFee`。如果 `sqrt(k)` 相比 `sqrt(kLast)` 增长，会按 Uniswap V2 风格给 `feeTo` 铸造协议 LP；fee 关闭后清空 `kLast`。

### Router

Router 提供：

- `addLiquidity` / `removeLiquidity`
- `addLiquidityETH` / `removeLiquidityETH`
- `swapExactTokensForTokens`
- `swapTokensForExactTokens`
- 多跳 swap、deadline 检查、滑点检查、多余 ETH refund

多跳 swap 中，中间输出直接发送到下一跳 Pair，只有最后一跳输出给用户。

### TWAP

Pair 在 `_update` 中维护：

- `price0CumulativeLast`
- `price1CumulativeLast`
- `blockTimestampLast`

`SimpleTwapOracle` 记录上次累计价格，等待固定 `period` 后用累计价格差值除以时间差得到平均价格。该 oracle 只用于 demo，不包含生产级抗操纵设计。

## 测试策略

测试包含单元测试、集成测试、fuzz 和 invariant：

| 测试文件 | 覆盖范围 |
| --- | --- |
| `Factory.t.sol` | Pair 创建、重复创建、token 排序、fee setter 权限 |
| `Library.t.sol` | quote、amount in/out、path 计算、swap 数学 fuzz |
| `Pair.t.sol` | mint、burn、swap、K revert、skim/sync、protocol fee、flash swap、permit、TWAP 累计价格 |
| `Router.t.sol` | 加减流动性、滑点、deadline、exact input/output、多跳 swap、path fuzz |
| `RouterETH.t.sol` | ETH/WETH 加减流动性、refund、Router receive 限制 |
| `SimpleTwapOracle.t.sol` | TWAP 更新、报价、period 限制、非法 token |
| `PairInvariant.t.sol` | reserve/balance 一致性、只 swap 场景下 K 不下降 |
| `DemoTokenFaucet.t.sol` | faucet 领取、暂停、补充资金、owner 权限 |

当前 `forge test`：`96 passed, 0 failed, 0 skipped`。

## 相关文档

- [`audit-notes.md`](audit-notes.md)：风险边界和已覆盖安全检查。
- [`slither-report.md`](slither-report.md)：Slither finding 分类和处理状态。
- [`debugging-archive.md`](debugging-archive.md)：开发中遇到的典型问题和修复索引。
