# Slither 静态分析记录

本文记录 mini-uniswap 的 Slither 结果和处理状态。Slither 对存在 finding 的项目会返回非零退出码，因此这里重点做人工分类，而不是把所有 finding 都视为同等严重问题。

## 运行方式

```bash
python3 -m venv /tmp/mini-uniswap-slither-venv
/tmp/mini-uniswap-slither-venv/bin/pip install slither-analyzer
/tmp/mini-uniswap-slither-venv/bin/slither . --exclude-dependencies
```

历史结果：

```text
初次：12 contracts analyzed, 77 result(s) found
处理后：13 contracts analyzed, 61 result(s) found
```

本轮处理后，未发现需要阻断学习项目继续推进的高危漏洞；剩余项主要是模式告警、设计预期或工程风格问题。

## 结果概览

| Detector | 主要位置 | 状态 |
| --- | --- | --- |
| `unchecked-transfer` | 初次出现在 `Pair.sol`、`Router.sol` | 已处理主要路径 |
| `reentrancy-no-eth` / `reentrancy-benign` / `reentrancy-events` | `Pair.burn`、`Pair.swap`、`Factory.createPair` | Pair 有 `lock`；flash swap callback 属于设计目标，继续记录 |
| `weak-prng` | `Pair._update` | 误报 / 低风险；timestamp 用于 TWAP，不是随机数 |
| `divide-before-multiply` | `Pair._update` | 可接受；UQ112x112 先除后乘有少量精度损失但降低溢出风险 |
| `incorrect-equality` | `Pair.mint` | 可接受；`totalSupply == 0` 是首次 mint 判断 |
| `unused-return` | `Library`、`Router` | 多数为解构丢弃值或不使用 `createPair` 返回值 |
| `missing-zero-check` | `Factory.setFeeTo` 等 | 关键路径已处理；`setFeeTo(address(0))` 保留用于关闭 protocol fee |
| `calls-loop` | `Router._swap` | 预期行为；多跳 swap 必然循环调用 Pair |
| `timestamp` | `Pair`、`UniERC20.permit`、Router deadline | 预期使用；TWAP、permit 和 deadline 需要 timestamp |
| `assembly` | `Factory.createPair`、`UniERC20.constructor` | 预期使用；CREATE2 和 chainid 需要 |
| `solc-version` | `pragma ^0.8.20` | 后续可固定 pragma 或升级 patch 版本 |
| `low-level-calls` | `TransferHelper` | 预期使用；兼容 ERC20 返回值差异 |
| `naming-convention` / `too-many-digits` / `constable-states` | 多处 | 风格 / 低风险项 |

## 已完成处理

1. Pair 内部转账改为 `TransferHelper.safeTransfer`。
2. Router 中 WETH transfer 和 LP `transferFrom` 显式检查返回值。
3. Router constructor 增加 `_factory` / `_WETH` 零地址检查。
4. Factory constructor 和 `setFeeToSetter` 增加零地址检查。
5. 部分状态变量改为 `constant` / `immutable`。
6. 补充 flash swap、protocol fee、permit、TWAP、ETH/WETH 和 invariant 测试。

## 保留项说明

- **Reentrancy 系列**：Pair 核心函数有 `lock`；`swap` callback 是 flash swap 的必要设计，callback 后通过余额和 K 值校验保证还款。
- **timestamp**：用于 TWAP 累计、permit deadline 和 Router deadline，不用于随机数。
- **calls-loop**：多跳 swap 的正常实现方式，path fuzz 已覆盖 single-hop 和 multi-hop。
- **assembly**：CREATE2 创建 Pair 和 EIP-712 domain separator 中读取 chain id 需要。
- **missing-zero-check / `setFeeTo`**：`setFeeTo(address(0))` 是关闭 protocol fee 的合法路径。

## 验证命令

```bash
forge fmt --check
forge test
/tmp/mini-uniswap-slither-venv/bin/slither . --exclude-dependencies
```

最近测试结果：

```text
96 tests passed, 0 failed, 0 skipped
```

Slither 处理后结果：

```text
13 contracts analyzed, 61 result(s) found
```

## 后续计划

1. 固定 Solidity pragma 或升级 compiler patch 版本。
2. 继续评估 Pair / Factory 的重入模式告警。
3. 统一命名风格和 revert message。
4. 只处理能带来真实安全收益的剩余 finding，避免为消除工具输出而引入无意义改动。
