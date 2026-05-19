# 排错归档

本文记录开发和补测试过程中遇到的典型问题。这里保留可复盘的结论，完整代码以当前 `src/` 和 `test/` 为准。

## 问题索引

| 问题 | 现象 | 原因 | 修复 / 回归 |
| --- | --- | --- | --- |
| TWAP 累计价格为 0 | 时间推进后 `price0CumulativeLast` / `price1CumulativeLast` 不增长 | `uint112 reserve << 112` 先在窄类型中左移，结果被截断 | 改为 `(uint256(reserve) << 112)`；回归 `testPriceCumulativeUpdatesAfterTimeElapsed` |
| `kLast()` 无法外部读取 | 接口声明 `kLast()`，但实现没有 getter | `kLast` 状态变量未声明为 `public` | 改为 `uint256 public kLast`；回归 protocol fee 测试 |
| flash swap 少还款 | callback 拿走 token 后必须 revert | flash swap 安全性依赖 callback 后的余额反推和 K 值校验 | 补足额还款成功、少还款 `K` revert 测试 |
| ETH/WETH LP 断言误差 | 首次 LP 或 remove 断言差 1000 wei 左右 | 忽略 `MINIMUM_LIQUIDITY` 或 burn 按 totalSupply 比例计算 | 测试按协议公式计算 expected value |
| `forge fmt --check` 失败 | CI / 本地格式检查输出 diff | 新增代码未按 Foundry formatter 格式化 | 运行 `forge fmt` 后再 `forge fmt --check` |
| Library fuzz 溢出 | fuzz counterexample 触发 arithmetic overflow | 输入范围接近 `uint256.max`，测试断言自身溢出 | 用 `bound` 限制到合理资产规模 |
| Router exact-input fuzz 输出为 0 | `amountIn = 1` 时 Pair 因 `insufficient output amount` revert | 整数除法和手续费导致极小输入输出为 0 | 成功路径 fuzz 下限调高；极小输入可单独写 revert 测试 |

## 关键经验

### 1. 类型转换顺序比表面代码更重要

`uint256(reserve << 112)` 和 `(uint256(reserve) << 112)` 不等价。前者先在 `uint112` 语义下左移，后者先扩展到 `uint256` 再左移。TWAP 累计价格 bug 就来自这个顺序问题。

### 2. 测试应验证协议公式，不要硬记魔法数字

LP mint/burn、ETH/WETH 路径和 protocol fee 都有整数除法、向下取整或 `MINIMUM_LIQUIDITY` 影响。更稳的测试方式是按当前状态和协议公式计算 expected value。

### 3. Fuzz 输入域要贴合协议语义

AMM 数学不是对所有 `uint256` 都有业务意义。对 reserve、amount in/out 做合理 `bound`，可以让 fuzz 聚焦有效状态；极端无效输入应放到专门的 revert 测试里。

### 4. Flash swap 的安全点在最终校验

Pair 允许 callback 先拿走 token，但 callback 后会读取真实余额，反推出输入量，并执行带手续费的 K 值校验。测试必须覆盖足额还款和少还款两条路径。

### 5. 工具输出要分类处理

Slither finding、formatter diff 和 fuzz counterexample 不一定都代表合约漏洞。处理顺序应是：先判断是否真实安全问题，再决定修复、补测试或文档说明。

## 当前回归命令

```bash
forge fmt --check
forge test
```

当前结果：

```text
96 tests passed, 0 failed, 0 skipped
```

常用定位命令：

```bash
forge test --match-contract PairTest -vvv
forge test --match-contract LibraryTest -vvv
forge test --match-contract RouterETHTest -vvv
forge test --match-contract PairReserveInvariantTest -vvv
forge test --match-contract PairSwapKInvariantTest -vvv
```

## 后续可继续归档

- Router path 边界问题。
- protocol fee 多轮 swap 后的精确数量断言。
- TWAP demo 的窗口选择和异常价格处理。
- Slither 剩余 finding 的后续处理结果。
