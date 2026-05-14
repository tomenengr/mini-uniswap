# 排错归档

本文记录 mini-uniswap 开发和补测试过程中遇到的典型问题。每个问题都按“现象、复现方式、错误原因、修复代码、讲解要点”整理，方便后续复盘、面试讲解和回归测试。

## 1. TWAP 累计价格始终为 0

### 现象

补 TWAP 测试时，时间推进后调用 `sync()`，预期 `price0CumulativeLast` 和 `price1CumulativeLast` 增长，但实际值仍然是 0。

失败信息类似：

```text
FAIL: assertion failed: 0 != 51922968585348276285304963292200960
```

### 复现测试

测试文件：[test/Pair.t.sol](../test/Pair.t.sol)

核心测试：

```solidity
function testPriceCumulativeUpdatesAfterTimeElapsed() public {
    _addLiquidity(alice, 10 ether, 10 ether);

    vm.warp(block.timestamp + 10);
    pair.sync();

    assertEq(pair.price0CumulativeLast(), uint256(1 << 112) * 10);
    assertEq(pair.price1CumulativeLast(), uint256(1 << 112) * 10);
}
```

另一个更明确的测试会验证 reserve 变化时，累计价格先按旧 reserve 计算上一段时间：

```solidity
function testPriceCumulativeUsesOldReservesBeforeSync() public {
    _addLiquidity(alice, 10 ether, 20 ether);

    vm.warp(block.timestamp + 5);
    token0.transfer(address(pair), 10 ether);
    pair.sync();

    uint256 expectedPrice0FirstPeriod = (uint256(20 ether) << 112) / 10 ether * 5;
    uint256 expectedPrice1FirstPeriod = (uint256(10 ether) << 112) / 20 ether * 5;
    assertEq(pair.price0CumulativeLast(), expectedPrice0FirstPeriod);
    assertEq(pair.price1CumulativeLast(), expectedPrice1FirstPeriod);
}
```

### 错误原因

原代码：

```solidity
price0CumulativeLast += uint256(reserve1 << 112) / reserve0 * timeElapsed;
price1CumulativeLast += uint256(reserve0 << 112) / reserve1 * timeElapsed;
```

问题在于 `reserve0` 和 `reserve1` 是 `uint112`。表达式 `reserve1 << 112` 会先在 `uint112` 语义下执行左移，结果被截断，再转换成 `uint256`。

对于 `10 ether` 这类数值，左移 112 位后低 112 位通常变成 0，所以累计价格一直是 0。

这类 bug 很隐蔽，因为代码看起来已经写了 `uint256(...)`，但转换发生得太晚。

### 修复代码

修复文件：[src/Pair.sol](../src/Pair.sol)

修复前：

```solidity
price0CumulativeLast += uint256(reserve1 << 112) / reserve0 * timeElapsed;
price1CumulativeLast += uint256(reserve0 << 112) / reserve1 * timeElapsed;
```

修复后：

```solidity
price0CumulativeLast += (uint256(reserve1) << 112) / reserve0 * timeElapsed;
price1CumulativeLast += (uint256(reserve0) << 112) / reserve1 * timeElapsed;
```

关键是先把 `uint112` 转成 `uint256`，再左移 112 位。

### 讲解要点

- Uniswap V2 的价格累计使用 UQ112x112 定点数。
- `reserveOut << 112` 等价于 `reserveOut * 2^112`。
- Solidity 中表达式的类型转换顺序很重要。
- `uint256(reserve1 << 112)` 和 `(uint256(reserve1) << 112)` 不是一回事。
- 这个 bug 是通过补 TWAP 测试发现的，说明测试不是只验证已有功能，也能发现隐藏实现问题。

## 2. `kLast()` 接口存在，但 Pair 没有公开 getter

### 现象

接口 `IUniswapV2Pair` 中声明了：

```solidity
function kLast() external view returns (uint256);
```

但 `Pair.sol` 原本写的是：

```solidity
uint256 kLast;
```

这意味着外部合约或测试无法直接调用 `pair.kLast()`。当要补 protocol fee 测试时，无法观察 `kLast` 是否在 fee-on / fee-off 状态下正确更新。

### 复现测试

测试文件：[test/Pair.t.sol](../test/Pair.t.sol)

相关测试：

```solidity
function testFeeOnMintsProtocolLiquidityWhenKGrows() public {
    address feeTo = address(0xFEE);
    factory.setFeeTo(feeTo);

    _addLiquidity(alice, 10 ether, 10 ether);
    uint256 kLastAfterMint = pair.kLast();

    _swapToken0ForToken1(bob, 1 ether);
    assertEq(pair.balanceOf(feeTo), 0);

    _addLiquidity(alice, 1 ether, 1 ether);

    assertGt(pair.balanceOf(feeTo), 0);
    assertGt(pair.kLast(), kLastAfterMint);
}
```

### 错误原因

Solidity 只有 `public` 状态变量会自动生成 getter。接口声明了 `kLast()`，但实现合约里的变量不是 `public`，接口和实现不一致。

这不是 AMM 数学错误，而是合约可观察性和接口一致性问题。

### 修复代码

修复前：

```solidity
uint256 kLast;
```

修复后：

```solidity
uint256 public kLast;
```

### 讲解要点

- protocol fee 的测试需要观察 `kLast`。
- Uniswap V2 里 `kLast` 是判断协议费增长的关键状态。
- 接口、实现和测试三者要一致，否则测试会被迫绕过真实外部行为。

## 3. Flash swap 少还款必须触发 K revert

### 现象

Pair 的 `swap` 支持 `data.length > 0` 时调用：

```solidity
IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
```

如果 callback 拿走 token 后没有还够，交易必须 revert。这个逻辑不能只靠代码阅读，需要测试验证。

### 复现测试

辅助合约：[test/Mocks.t.sol](../test/Mocks.t.sol)

```solidity
contract FlashSwapCallee is IUniswapV2Callee {
    enum Mode {
        Repay,
        Underpay,
        DoNothing
    }

    Mode public mode;

    function setMode(Mode _mode) external {
        mode = _mode;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        (address token0, address token1) = abi.decode(data, (address, address));

        if (mode == Mode.DoNothing) return;

        if (amount0 > 0) {
            uint256 repay0 = mode == Mode.Underpay ? amount0 : amount0 * 1004 / 1000 + 1;
            ERC20(token0).transfer(msg.sender, repay0);
        }

        if (amount1 > 0) {
            uint256 repay1 = mode == Mode.Underpay ? amount1 : amount1 * 1004 / 1000 + 1;
            ERC20(token1).transfer(msg.sender, repay1);
        }
    }
}
```

失败路径测试：

```solidity
function testFlashSwapUnderpaymentRevertsK() public {
    _addLiquidity(alice, 10 ether, 10 ether);
    FlashSwapCallee callee = new FlashSwapCallee();
    callee.setMode(FlashSwapCallee.Mode.Underpay);
    token1.transfer(address(callee), 1 ether);

    vm.expectRevert(bytes("K"));
    pair.swap(0, 1 ether, address(callee), abi.encode(address(token0), address(token1)));
}
```

成功路径测试：

```solidity
function testFlashSwapRepaidCallbackSucceeds() public {
    _addLiquidity(alice, 10 ether, 10 ether);
    FlashSwapCallee callee = new FlashSwapCallee();
    token1.transfer(address(callee), 1 ether);

    pair.swap(0, 1 ether, address(callee), abi.encode(address(token0), address(token1)));

    (uint112 r0, uint112 r1,) = pair.getReserves();
    assertEq(token0.balanceOf(address(pair)), r0);
    assertEq(token1.balanceOf(address(pair)), r1);
}
```

### 错误原因

这里不是已经发现的实现 bug，而是一个必须用测试锁住的安全假设。

flash swap 的核心模式是：

1. Pair 先把 token 转给 `to`。
2. 如果有 data，就调用 callback。
3. callback 必须在同一笔交易中还回足够资产。
4. Pair 最后用实际余额反推出输入量，并检查 K 值。

如果第 4 步缺失或测试不到位，flash swap 就可能变成无抵押提款。

### 关键代码

[src/Pair.sol](../src/Pair.sol)

```solidity
if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);

uint256 balance0 = ERC20(token0).balanceOf(address(this));
uint256 balance1 = ERC20(token1).balanceOf(address(this));

uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
require(amount0In > 0 || amount1In > 0, "insufficient input amount");

uint256 balance0Adjusted = balance0 * 1000 - (amount0In * 3);
uint256 balance1Adjusted = balance1 * 1000 - (amount1In * 3);
require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * (1000 ** 2), "K");
```

### 讲解要点

- flash swap 的安全性不来自提前收钱，而来自交易结束时的 K 校验。
- callback 可以执行任意逻辑，但必须让 Pair 最终余额满足 invariant。
- `amountIn` 不是用户传参，而是 Pair 通过余额差计算出来的。

## 4. ETH/WETH 首次 LP 和移除流动性不能用手写常数断言

### 现象

补 `addLiquidityETH` 和 `removeLiquidityETH` 测试时，如果直接手写预期值，容易出现几百 wei 到 1000 wei 级别的误差。

失败信息类似：

```text
assertion failed: 7071067811865474244 != 7071067811865475244
assertion failed: 9999999999999998585 != 9999999999999999000
```

### 复现测试

测试文件：[test/RouterETH.t.sol](../test/RouterETH.t.sol)

首次添加流动性：

```solidity
function testAddLiquidityETHCreatesPairAndMintsLp() public {
    vm.startPrank(alice);
    token.approve(address(router), 10 ether);
    (uint256 amountToken, uint256 amountETH, uint256 liquidity) =
        router.addLiquidityETH{value: 5 ether}(address(token), 10 ether, 0, 0, alice, block.timestamp);
    vm.stopPrank();

    assertEq(amountToken, 10 ether);
    assertEq(amountETH, 5 ether);
    assertEq(liquidity, 7071067811865474244);
}
```

移除流动性更推荐按公式算：

```solidity
uint256 totalSupplyBefore = pair.totalSupply();
uint256 expectedToken = liquidity * token.balanceOf(address(pair)) / totalSupplyBefore;
uint256 expectedETH = liquidity * weth.balanceOf(address(pair)) / totalSupplyBefore;

router.removeLiquidityETH(address(token), liquidity, 0, 0, alice, block.timestamp);

assertEq(amountToken, expectedToken);
assertEq(amountETH, expectedETH);
```

### 错误原因

首次 LP 数量不是简单的几何平均数，而是：

```text
liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
```

而移除流动性时，返还数量是：

```text
amount = liquidity * balance / totalSupply
```

如果 token 和 ETH 比例不是 1:1，或者忽略 `MINIMUM_LIQUIDITY`，手写常数很容易错。

### 修复方式

测试里尽量使用协议公式推导 expected value：

```solidity
uint256 totalSupplyBefore = pair.totalSupply();
uint256 expectedToken = liquidity * token.balanceOf(address(pair)) / totalSupplyBefore;
uint256 expectedETH = liquidity * weth.balanceOf(address(pair)) / totalSupplyBefore;
```

### 讲解要点

- 测试应该验证协议公式，而不是记忆某个魔法数字。
- `MINIMUM_LIQUIDITY` 会永久锁定一小部分份额，影响首次 mint 和最终 burn。
- 非 1:1 池子的 burn 结果必须按 LP 占总供应比例计算。

## 5. `forge fmt --check` 因格式不一致失败

### 现象

新增测试后，`forge fmt --check` 失败并输出 diff，例如函数签名换行、`keccak256` 格式不符合 Foundry formatter。

示例：

```text
Diff in test/Library.t.sol:
function testFuzzGetAmountOutMatchesFormula(...) public view {

Diff in test/Pair.t.sol:
bytes32 structHash = keccak256(
    abi.encode(...)
);
```

### 复现方式

运行：

```bash
forge fmt --check
```

如果格式不符合 Foundry 默认规则，CI 中的格式检查也会失败。

### 修复方式

本地运行：

```bash
forge fmt
```

然后再检查：

```bash
forge fmt --check
```

### 讲解要点

- CI 中已经配置 `forge fmt --check`，格式问题会阻断 push/PR 检查。
- `forge fmt` 是自动格式化，`forge fmt --check` 是只检查不修改。
- 这类问题不是业务 bug，但属于工程规范的一部分。

## 6. Fuzz 测试输入范围过大导致测试自身溢出

### 现象

给 `Library.getAmountIn` 补 fuzz 测试时，Foundry 生成了极大的输入值，导致测试断言里的二次计算溢出。

失败信息类似：

```text
panic: arithmetic underflow or overflow (0x11)
counterexample: ...
```

### 复现测试

测试文件：[test/Library.t.sol](../test/Library.t.sol)

目标是验证：

```solidity
uint256 amountIn = harness.getAmountIn(amountOut, reserveIn, reserveOut);
uint256 actualOut = harness.getAmountOut(amountIn, reserveIn, reserveOut);

assertGe(actualOut, amountOut);
```

### 错误原因

被测函数本身用常规 AMM 数学计算，但 fuzz 输入如果接近 `uint256.max`，测试中的乘法也会溢出。

这不是业务逻辑一定错误，而是测试输入范围没有贴合协议合理资产规模。

### 修复代码

修复后对 fuzz 输入做边界限制：

```solidity
reserveIn = bound(reserveIn, 1, 1e22);
reserveOut = bound(reserveOut, 2, 1e22);
amountOut = bound(amountOut, 1, reserveOut - 1);
```

### 讲解要点

- fuzz 不是越大越好，输入域要符合协议合理范围。
- 对 AMM 数学测试，需要避免测试代码自身因为极端输入溢出。
- `bound` 的作用是把随机输入映射到有意义的测试区间。

## 7. Router exact-input fuzz 中 1 wei 输入导致输出为 0

### 现象

补 Router path fuzz 时，Foundry 生成 `amountIn = 1`，`Library.getAmountsOut` 算出的输出为 0。Router 继续执行 swap，最终 Pair 因为输出为 0 revert：

```text
insufficient output amount
```

### 复现测试

测试文件：[test/Router.t.sol](../test/Router.t.sol)

相关测试：

```solidity
function testFuzzSwapExactTokensForTokensSingleHop(uint256 amountIn) public {
    _addLiquidity(alice, tokenA, tokenB, 100 ether, 100 ether);
    amountIn = bound(amountIn, 1e9, 10 ether);
    ...
}
```

### 错误原因

AMM 使用整数除法。极小输入在手续费和除法舍入后，可能得到 0 输出：

```text
amountOut = amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee)
```

当 `amountOut == 0` 时，Pair 的 `swap(0, 0, ...)` 会正确 revert。

### 修复方式

将 fuzz 输入范围调整到能产生非零输出的有效区间：

```solidity
amountIn = bound(amountIn, 1e9, 10 ether);
```

### 讲解要点

- 这是测试输入域问题，不是 Router 路径逻辑错误。
- fuzz 测试要覆盖有效输入域，也要理解协议对无效输入的自然 revert。
- 如果想专门覆盖极小输入，可以另写 revert 测试，而不是放在成功路径 fuzz 中。

## 当前回归命令

每次修复后至少运行：

```bash
forge fmt --check
forge test
```

当前结果：

```text
88 tests passed, 0 failed, 0 skipped
```

如果只想复现某类问题，可以运行：

```bash
forge test --match-contract PairTest -vvv
forge test --match-contract LibraryTest -vvv
forge test --match-contract RouterETHTest -vvv
```

## 后续可继续归档的问题

- Router path fuzz 发现的路径边界问题。
- protocol fee 精确数量断言中可能出现的四舍五入问题。
- Slither 静态分析发现的问题和处理结果。
- TWAP demo 或 consumer library 中的窗口选择问题。
