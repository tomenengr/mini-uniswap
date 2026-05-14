# 设计说明

Mini Uniswap V2 是一个使用 Solidity + Foundry 实现的简化版 Uniswap V2 风格 AMM。项目目标不是完整复制生产协议，而是把核心机制写清楚、测清楚：确定性交易对部署、LP Token 铸造与销毁、恒定乘积 swap、reserve 记账、Router 层滑点保护，以及基础安全约束。

本项目用于学习和作品集展示，不适合直接用于生产环境或真实资金。

## 整体架构

系统分为四个核心层：

| 层级 | 合约 | 职责 |
| --- | --- | --- |
| Factory | `Factory.sol` | 使用 CREATE2 创建交易对，并记录 Pair 地址 |
| Pair | `Pair.sol` | 持有资金池资产，维护 reserves，铸造/销毁 LP，执行 swap |
| Router | `Router.sol` | 面向用户的入口，封装加减流动性和 swap 流程 |
| Library | `Library.sol` | 提供排序、Pair 地址预测、reserve 查询和价格计算辅助函数 |
| Oracle | `SimpleTwapOracle.sol` | 示例 TWAP oracle，消费 Pair 累计价格并计算平均价格 |

典型调用路径：

```text
User -> Router -> Factory
              -> Pair
              -> ERC20 tokens
```

用户通常只需要和 Router 交互。Router 负责计算最优数量、把 token 转入 Pair、再调用 Pair 的核心函数。Pair 是资金池状态的最终来源，负责维护 token balance、reserve、LP totalSupply 和 swap invariant。

## Pair 创建

Factory 对每组 token 只创建一个 Pair。创建前先对 token 地址排序：

```solidity
(token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
```

这样可以保证 `getPair[tokenA][tokenB]` 和 `getPair[tokenB][tokenA]` 指向同一个 Pair。

Pair 使用 CREATE2 部署：

```text
pair = address(keccak256(0xff ++ factory ++ salt ++ init_code_hash))
salt = keccak256(token0 ++ token1)
```

`Library.pairFor` 使用同一套计算方式，因此 Router 可以在不额外调用 `getPair` 的情况下预测 Pair 地址。

## Reserve 与 Balance

每个 Pair 存储：

```solidity
uint112 reserve0;
uint112 reserve1;
uint32 blockTimestampLast;
```

ERC20 的 `balanceOf(pair)` 是真实资产余额，`reserve0/reserve1` 是上一次同步后的账面库存。Pair 的核心操作都遵循类似流程：

1. 读取当前 token balance。
2. 与旧 reserve 对比。
3. 计算输入量、输出量或流动性数量。
4. 校验流动性、滑点或 K 值约束。
5. 调用 `_update` 把 reserve 同步到当前 balance。

`skim` 会把 balance 中超过 reserve 的部分转给目标地址。`sync` 会把 reserve 直接更新为当前 balance。

## 添加流动性

LP 先把两个 token 转入 Pair，再调用 `mint`。

第一次添加流动性：

```text
liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
```

`MINIMUM_LIQUIDITY` 会永久铸造给 `address(0)`。这和 Uniswap V2 原设计一致，用于避免第一个 LP 完全移除池子份额。

后续添加流动性：

```text
liquidity = min(
    amount0 * totalSupply / reserve0,
    amount1 * totalSupply / reserve1
)
```

较少的一边决定最终 LP 数量。如果用户直接向 Pair 转入了不平衡比例，多余资产会暂留在 Pair 中，后续可被未来操作吸收，或通过 `skim` 取出。

Router 的 `addLiquidity` 会在 Pair 不存在时自动创建 Pair，并根据当前 reserve 计算最优添加比例。`addLiquidityETH` 会把 ETH 包装成 WETH 后转入 Pair。

## 移除流动性

移除流动性时，LP token 先转入 Pair，然后调用 `burn`：

```text
amount0 = liquidity * balance0 / totalSupply
amount1 = liquidity * balance1 / totalSupply
```

Pair 销毁自己持有的 LP token，并把底层 token 发送给接收者。Router 会封装这一流程：从用户处拉取 LP、调用 `burn`、根据 token 顺序翻译输出数量，并检查最小接收量。

`removeLiquidityETH` 会先收到 WETH，再调用 WETH `withdraw` 解包为 ETH，最后把 ETH 转给用户。

## Swap 公式

AMM 使用恒定乘积模型：

```text
x * y = k
```

exact input swap 中，输出数量按 0.3% 手续费计算：

```text
amountInWithFee = amountIn * 997
amountOut = amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee)
```

exact output swap 中，输入数量为：

```text
amountIn = reserveIn * amountOut * 1000 / ((reserveOut - amountOut) * 997) + 1
```

最后的 `+ 1` 用于向上取整，避免整数除法导致输入不足。

## K 值约束

Pair 在转出 token 和执行可选 callback 后，再读取实际 balance，并反推出真实输入数量：

```text
amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0
amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0
```

然后执行带手续费的 K 值校验：

```text
balance0Adjusted = balance0 * 1000 - amount0In * 3
balance1Adjusted = balance1 * 1000 - amount1In * 3

balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000^2
```

这是 swap 的核心安全检查。flash swap 也依赖这个模式：callback 可以先拿到 token，但在交易结束前必须还回足够资产，否则 K 校验会失败。

## Protocol Fee

Pair 实现了简化版 Uniswap V2 protocol fee 逻辑：

- `Factory.feeTo()` 非零时，协议费开启。
- Pair 在 `mint` / `burn` 中调用 `_mintFee`。
- 如果 `sqrt(k)` 相比 `sqrt(kLast)` 增长，会给 `feeTo` 铸造一部分 LP token。
- fee 关闭后，如果 `kLast` 非零，会清零 `kLast`。

`kLast` 已对外暴露为 `public`，便于测试和观察 fee-on / fee-off 状态变化。

## Router 行为

Router 提供更适合用户使用的接口：

- `addLiquidity`：必要时创建 Pair，计算最优添加比例，转入 token，铸造 LP。
- `addLiquidityETH`：支持 ETH 作为一边资产，多余 ETH 会退款。
- `removeLiquidity`：转入 LP，调用 Pair `burn`，检查最小输出。
- `removeLiquidityETH`：移除 token/WETH 流动性，并把 WETH 解包为 ETH。
- `swapExactTokensForTokens`：exact input swap，检查最小输出。
- `swapTokensForExactTokens`：exact output swap，检查最大输入。
- `ensure(deadline)`：拒绝过期交易。

多跳 swap 中，中间 Pair 的输出会直接发送到下一个 Pair，只有最后一跳输出发送给用户。

## TWAP Oracle 示例

`SimpleTwapOracle.sol` 演示如何消费 Pair 的累计价格字段：

1. 构造函数记录初始 `price0CumulativeLast`、`price1CumulativeLast` 和 Pair timestamp。
2. `update()` 在 `period` 结束后读取当前累计价格。
3. 用累计价格差值除以时间差，得到 `price0Average` 和 `price1Average`。
4. `consult(tokenIn, amountIn)` 使用平均价格计算 TWAP 报价。

该合约是教学 demo，不是生产级 oracle。生产环境还需要考虑窗口选择、操纵成本、更新权限、异常价格处理和多数据源保护。

## 测试策略

测试按模块组织：

| 测试文件 | 覆盖范围 |
| --- | --- |
| `Factory.t.sol` | Pair 创建、重复创建、token 排序、fee setter 权限 |
| `Library.t.sol` | token 排序、quote、swap 数学、path 数量计算、swap 数学 fuzz |
| `Pair.t.sol` | mint、burn、swap、K revert、skim/sync、protocol fee 精确数量、flash swap、permit、TWAP 累计价格 |
| `Router.t.sol` | 加减流动性、滑点、deadline、exact input/output swap、多跳 swap、Router path fuzz |
| `RouterETH.t.sol` | `addLiquidityETH`、ETH refund、`removeLiquidityETH`、Router receive 限制 |
| `SimpleTwapOracle.t.sol` | TWAP oracle 更新、报价、period 限制和非法 token |
| `PairInvariant.t.sol` | reserve/balance 一致性、只 swap 场景下 K 不下降 |
| `PairForAndReserves.t.sol` | CREATE2 Pair 地址预测、reserve 顺序映射 |

当前测试既包含确定性单元/集成测试，也包含 Foundry fuzz 和 invariant 测试。后续可以继续补充：

- Router ETH 路径的失败分支。
- 根据 Slither 结果进行安全和工程细节加固。

## 排错归档

开发过程中遇到的典型问题已整理在 [`debugging-archive.md`](debugging-archive.md)，包括 TWAP 左移截断、`kLast` getter、flash swap 少还款、ETH/WETH 测试预期、格式检查和 fuzz 输入范围等问题。

## 静态分析

Slither 静态分析结果已整理在 [`slither-report.md`](slither-report.md)，包括 unchecked transfer、重入模式告警、timestamp、zero-check、calls-loop、compiler version、constant/immutable 等 finding 的分类和处理计划。
