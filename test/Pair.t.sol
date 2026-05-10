// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/ERC20.sol";

contract PairTest is Test {
    Factory factory;
    Pair pair;
    ERC20 token0;
    ERC20 token1;

    address alice = address(0x1);

    function setUp() public {
        // 1. 部署环境
        factory = new Factory(address(this));
        token0 = new ERC20("Token 0", "TK0");
        token1 = new ERC20("Token 1", "TK1");

        // 2. 创建 Pair (注意 token0/token1 的排序由 Factory 决定)
        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = Pair(pairAddress);

        // 3. 排序确认 (确保我们在测试里逻辑清晰)
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // 4. 给 Alice 一点钱
        token0.transfer(alice, 1000 ether);
        token1.transfer(alice, 1000 ether);
    }

    function testFirstMint() public {
        uint256 amount0 = 10 ether;
        uint256 amount1 = 10 ether;

        // 在 Foundry 里切换到 Alice 的身份
        vm.startPrank(alice);

        // Uniswap 的玩法：先转账到 Pair，再调用 mint
        token0.transfer(address(pair), amount0);
        token1.transfer(address(pair), amount1);

        // 第一次铸造 LP
        uint256 liquidity = pair.mint(alice);

        vm.stopPrank();

        // 验证结果：
        // 第一次流动性公式: sqrt(10 * 10) - 1000/1e18
        // 也就是 10 ether - 1000
        uint256 expectedLiquidity = 10 ether - 1000;
        assertEq(liquidity, expectedLiquidity, "Liquidity mismatch");
        assertEq(pair.balanceOf(alice), expectedLiquidity, "Alice LP balance mismatch");

        // 验证 Reserve 更新了
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, amount0);
        assertEq(r1, amount1);
    }

    function testMintInsufficientLiquidity() public {
        // 故意只转 1 wei 进去，看它会不会报错
        vm.startPrank(alice);
        token0.transfer(address(pair), 1);
        token1.transfer(address(pair), 1);

        // 我们预期它会 revert，并抛出错误信息
        vm.expectRevert("insufficient liquidity minted");
        pair.mint(alice);
        vm.stopPrank();
    }
}
