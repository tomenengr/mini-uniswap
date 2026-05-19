# 审计笔记

本文记录 Mini Uniswap V2 的审查范围、已知限制、已覆盖安全检查和后续计划。项目定位是学习成果展示，不是生产级 DeFi 协议。

## 审查范围

已纳入：

- `Factory.sol`
- `Pair.sol`
- `Router.sol`
- `Library.sol`
- `TransferHelper.sol`
- `ERC20.sol`
- `UniERC20.sol`
- `DemoTokenFaucet.sol`
- interfaces

未纳入：

- 主网部署安全性
- 形式化验证
- 深度 gas 优化
- 经济攻击模拟
- 生产级 oracle 方案
- 非标准 token 兼容性

## 已知限制

| 范围 | 限制 | 影响 |
| --- | --- | --- |
| 协议定位 | 学习型简化实现 | 不适合真实资金环境 |
| ERC20 假设 | 不支持 fee-on-transfer、rebasing、pausable、blacklist、复杂 callback token | Router 计算数量可能与实际到账不一致 |
| Oracle | `SimpleTwapOracle` 只演示固定窗口 TWAP | 缺少抗操纵窗口、异常价格处理、更新权限和多数据源保护 |
| Flash swap | 已覆盖基础还款/少还款路径 | 尚未覆盖双 token 借出、复杂 callback 和更细重入场景 |
| Protocol fee | 已覆盖关键路径和精确铸造 | 仍可补多次 swap、mint/burn 和 fee on/off 切换边界 |
| 访问控制 | `feeToSetter` 单点权限 | 无 timelock、multisig 或治理延迟 |

## 已实现安全检查

- **Pair 重入锁**：`mint`、`burn`、`swap`、`skim`、`sync` 使用 `lock`。
- **K 值校验**：swap 和 flash swap 最终都必须满足带 0.3% fee 的恒定乘积约束。
- **滑点与 deadline**：Router 检查最小接收量、最大输入量和交易过期时间。
- **CREATE2 确定性**：`Factory.createPair` 与 `Library.pairFor` 使用相同 salt 和 init code hash 逻辑。
- **安全转账**：Pair 内部转账和 Router 关键路径使用 `TransferHelper` 或显式检查返回值。
- **零地址检查**：Factory、Router、Pair 初始化等关键入口已加基础零地址校验。
- **LP permit 测试**：覆盖有效签名、过期签名、错误 signer 和 nonce replay。

## 测试覆盖

当前 `forge test`：`96 passed, 0 failed, 0 skipped`。

重点安全测试：

- K 值破坏时 revert。
- flash swap 足额还款成功、少还款 revert。
- reserve/balance 一致性 invariant。
- 只 swap 场景下 K 不下降 invariant。
- `Library` swap 数学 fuzz。
- Router single-hop / multi-hop path fuzz。
- ETH/WETH refund、remove unwrap 和 Router receive 限制。
- protocol fee 精确 LP 铸造和 `kLast` 清零。

## Slither 摘要

完整记录见 [`slither-report.md`](slither-report.md)。

当前已处理：

- Pair 内部 unchecked transfer。
- Router 关键返回值检查。
- Router/Factory 关键零地址检查。
- 部分 `constant` / `immutable` 优化。

剩余 finding 多数属于设计预期、教学简化或低风险风格项，例如 callback 重入模式告警、timestamp、calls-loop、assembly、pragma 固定和命名风格。

## 后续计划

1. 固定 Solidity pragma 或升级 compiler patch 版本后重跑完整测试。
2. 继续补 ETH/WETH、flash swap、protocol fee 的边界 fuzz / invariant。
3. 统一 revert message 和命名风格。
4. 如果要接近生产协议，需要补治理权限、oracle 抗操纵设计、非标准 token 策略和更完整的经济攻击分析。
