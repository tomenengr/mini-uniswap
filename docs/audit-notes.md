# 审计笔记

本文记录 Mini Uniswap V2 当前已知风险、设计限制、已覆盖安全检查和后续审查计划。

项目定位是学习和作品集展示，未经过正式审计，不应部署到生产环境或承载真实资金。

## 审查范围

已纳入审查的组件：

- `Factory.sol`
- `Pair.sol`
- `Router.sol`
- `Library.sol`
- `TransferHelper.sol`
- `ERC20.sol`
- `UniERC20.sol`
- interfaces

不在当前范围内：

- 主网部署安全性
- 形式化验证
- 深度 gas 优化
- 经济攻击模拟
- 生产级 oracle 方案
- 真实非标准 token 兼容性

## 已知限制

### 不是生产级协议

当前实现刻意保持简化，适合学习 AMM 机制和展示工程能力，但没有达到生产 DeFi 合约需要的完整加固水平。

### ERC20 假设较简单

Pair 和 Router 默认 token 遵守标准 ERC20 行为。目前不支持：

- fee-on-transfer token
- rebasing token
- pausable token
- blacklist token
- 回调逻辑复杂的 token
- 返回值不标准的 token

潜在影响：

- 实际到账数量可能和 Router 计算数量不同。
- reserve 记账可能偏离真实预期。
- swap 输出和滑点判断可能不再准确。

### ETH/WETH 路径已补基础测试，但仍可加深

当前已经使用 `MockWETH` 覆盖：

- `addLiquidityETH`
- 多余 ETH refund
- `removeLiquidityETH`
- Router `receive()` 只接受 WETH

仍可继续补充：

- token/WETH 比例不平衡时的最优数量计算。
- ETH 路径下的滑点失败用例。
- WETH `withdraw` 失败或接收方拒收 ETH 的边界行为。

### Oracle / TWAP 已补基础测试，但尚未生产完整

`Pair.sol` 包含 `price0CumulativeLast` 和 `price1CumulativeLast`。当前已经覆盖基础累计价格测试，包括时间推进后的累计价格增长，以及 reserve 变化时先按旧 reserve 累计上一段时间。

缺失内容包括：

- 面向调用方的 TWAP library。
- 抗操纵窗口设计。
- 更复杂交易序列下的 TWAP 行为验证。

### Flash Swap 已有基础测试，但还不是完整攻击面覆盖

`swap` 在 `data.length > 0` 时会调用 `uniswapV2Call`。Pair 在 callback 之后执行 K 值校验，这是 flash swap 的核心安全模式。

当前已覆盖：

- callback 中足额还款成功。
- callback 中少还款触发 `K` revert。

仍可继续补充：

- 同时借出 token0/token1 的场景。
- callback receiver 校验 `msg.sender` 是否为 Pair。
- callback 中执行复杂外部调用的行为。
- 更明确的重入假设测试。

### Protocol Fee 已补关键路径测试，但可继续精确化

`Pair._mintFee` 实现了 `feeTo`、`kLast`、`rootK`、`rootKLast` 和协议 LP 铸造逻辑。

当前已覆盖：

- fee off 时不铸造协议 LP。
- fee on 后，swap 增大 K，再 add liquidity 会给 `feeTo` 铸造 LP。
- feeTo 关闭后，`kLast` 清零。
- `kLast` 对外可读，用于验证 fee 状态。

后续可继续补充：

- 协议 LP 铸造数量的精确公式断言。
- 多次 swap 后再 mint/burn 的 fee 累积行为。
- fee on / off 多次切换的边界场景。

### Permit 已补基础测试

`UniERC20` 包含 LP token 的 `permit` 实现。当前已覆盖：

- 有效 EIP-712 签名可以设置 allowance。
- 过期 permit 会 revert。
- 错误 signer 会 revert。
- nonce replay 会失败。

后续可继续补充 deadline 边界值和更多签名参数组合。

### 访问控制较轻

Factory 只限制 `setFeeTo` 和 `setFeeToSetter` 必须由 `feeToSetter` 调用。当前没有 timelock、multisig 或治理延迟。

这对学习项目可以接受，但如果面向生产，需要更完整的治理和权限管理设计。

## 已实现安全检查

### Pair 重入锁

Pair 的关键状态变更函数使用简单锁：

```solidity
modifier lock()
```

覆盖函数包括：

- `mint`
- `burn`
- `swap`
- `skim`
- `sync`

### Swap K 值校验

swap 执行带 0.3% 手续费的恒定乘积约束：

```text
balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000^2
```

测试已覆盖破坏 K 值时 revert，以及 flash swap 少还款时 revert。

### Reserve / Balance 一致性 invariant

新增 Foundry invariant 测试，通过 handler 随机执行：

- 添加流动性
- token0 -> token1 swap
- token1 -> token0 swap
- `skim`
- `sync`

并持续检查：

```solidity
token0.balanceOf(address(pair)) == reserve0
token1.balanceOf(address(pair)) == reserve1
```

### 只 swap 场景下 K 不下降 invariant

在只允许 swap、不允许 burn 的 handler 中，测试持续检查当前 K 不低于初始 K，并记录每次 swap 后 K 是否单调不下降。

### Library swap 数学 fuzz

`Library.t.sol` 已对核心数学函数增加 fuzz 测试：

- `quote` 输出匹配比例公式。
- `getAmountOut` 输出匹配 0.3% fee 公式，且输出小于 reserveOut。
- `getAmountIn` 计算出的输入量可以换出不少于目标输出量。

### Router deadline 检查

Router 用户入口使用：

```solidity
modifier ensure(uint256 deadline)
```

过期操作会 revert：`expired`。

### Router 滑点检查

Router 会检查：

- 添加流动性的最小 token 数量。
- 移除流动性的最小 token 数量。
- exact input swap 的最小输出。
- exact output swap 的最大输入。

### CREATE2 地址确定性

`Factory.createPair` 和 `Library.pairFor` 使用相同的 salt 与 init code hash 逻辑。测试已验证预测 Pair 地址与实际部署地址一致。

## 后续建议

1. 补 Router path 的 fuzz test。
2. 补面向调用方的 TWAP library 或 TWAP demo。
3. 继续细化 protocol fee 的精确数量断言。
4. 给 Router ETH 路径补更多失败分支。
5. 统一 revert message 与命名风格。
6. 在测试和文档稳定后，再添加部署脚本或演示脚本。
