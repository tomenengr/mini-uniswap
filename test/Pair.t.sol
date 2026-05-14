// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/ERC20.sol";
import "../src/Library.sol";
import "../src/Math.sol";
import "./Mocks.t.sol";

contract PairTest is Test {
    Factory factory;
    Pair pair;
    ERC20 token0;
    ERC20 token1;

    address alice = address(0x1);
    address bob = address(0x2);
    uint256 permitOwnerKey = 0xA11CE;
    address permitOwner;

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

        // 4. 给测试账户一些 token
        token0.transfer(alice, 1000 ether);
        token1.transfer(alice, 1000 ether);
        token0.transfer(bob, 1000 ether);
        token1.transfer(bob, 1000 ether);
        permitOwner = vm.addr(permitOwnerKey);
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

    function testSecondMint() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        uint256 liquidity = _addLiquidity(alice, 5 ether, 5 ether);

        assertEq(liquidity, 5 ether);
        assertEq(pair.balanceOf(alice), 15 ether - pair.MINIMUM_LIQUIDITY());

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 15 ether);
        assertEq(r1, 15 ether);
    }

    function testSecondMintUsesLowerSideWhenRatioIsUnbalanced() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        uint256 liquidity = _addLiquidity(alice, 10 ether, 5 ether);

        assertEq(liquidity, 5 ether);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 20 ether);
        assertEq(r1, 15 ether);
    }

    function testBurn() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        uint256 liquidity = pair.balanceOf(alice);
        uint256 balance0Before = token0.balanceOf(alice);
        uint256 balance1Before = token1.balanceOf(alice);

        vm.startPrank(alice);
        pair.transfer(address(pair), liquidity);
        (uint256 amount0, uint256 amount1) = pair.burn(alice);
        vm.stopPrank();

        assertEq(amount0, 10 ether - pair.MINIMUM_LIQUIDITY());
        assertEq(amount1, 10 ether - pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(alice), balance0Before + amount0);
        assertEq(token1.balanceOf(alice), balance1Before + amount1);
        assertEq(pair.balanceOf(alice), 0);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, pair.MINIMUM_LIQUIDITY());
        assertEq(r1, pair.MINIMUM_LIQUIDITY());
    }

    function testRevertWhenBurnWithoutLiquidity() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.expectRevert("insufficient liquidity burned");
        pair.burn(alice);
    }

    function testSwapExactToken0ForToken1() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        uint256 amount0In = 1 ether;
        uint256 amount1Out = Library.getAmountOut(amount0In, 10 ether, 10 ether);

        vm.startPrank(bob);
        token0.transfer(address(pair), amount0In);
        pair.swap(0, amount1Out, bob, "");
        vm.stopPrank();

        assertEq(token1.balanceOf(bob), 1000 ether + amount1Out);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 10 ether + amount0In);
        assertEq(r1, 10 ether - amount1Out);
        assertEq(token0.balanceOf(address(pair)), r0);
        assertEq(token1.balanceOf(address(pair)), r1);
    }

    function testSwapExactToken1ForToken0() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        uint256 amount1In = 1 ether;
        uint256 amount0Out = Library.getAmountOut(amount1In, 10 ether, 10 ether);

        vm.startPrank(bob);
        token1.transfer(address(pair), amount1In);
        pair.swap(amount0Out, 0, bob, "");
        vm.stopPrank();

        assertEq(token0.balanceOf(bob), 1000 ether + amount0Out);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 10 ether - amount0Out);
        assertEq(r1, 10 ether + amount1In);
    }

    function testRevertWhenSwapHasNoOutput() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.expectRevert("insufficient output amount");
        pair.swap(0, 0, bob, "");
    }

    function testRevertWhenSwapOutputExceedsLiquidity() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.expectRevert("insufficient liquidity");
        pair.swap(0, 10 ether, bob, "");
    }

    function testRevertWhenSwapToTokenAddress() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.expectRevert("invalid to");
        pair.swap(0, 1 ether, address(token0), "");
    }

    function testRevertWhenSwapHasNoInput() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.expectRevert("insufficient input amount");
        pair.swap(0, 1 ether, bob, "");
    }

    function testRevertWhenSwapBreaksKInvariant() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.startPrank(bob);
        token0.transfer(address(pair), 1 ether);
        vm.expectRevert(bytes("K"));
        pair.swap(0, 2 ether, bob, "");
        vm.stopPrank();
    }

    function testSkimTransfersExcessBalances() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.startPrank(bob);
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.skim(bob);
        vm.stopPrank();

        assertEq(token0.balanceOf(bob), 1000 ether);
        assertEq(token1.balanceOf(bob), 1000 ether);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 10 ether);
        assertEq(r1, 10 ether);
    }

    function testSyncUpdatesReservesToCurrentBalances() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.startPrank(bob);
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 2 ether);
        pair.sync();
        vm.stopPrank();

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 11 ether);
        assertEq(r1, 12 ether);
    }

    function testPriceCumulativeUpdatesAfterTimeElapsed() public {
        _addLiquidity(alice, 10 ether, 10 ether);

        vm.warp(block.timestamp + 10);
        pair.sync();

        assertEq(pair.price0CumulativeLast(), uint256(1 << 112) * 10);
        assertEq(pair.price1CumulativeLast(), uint256(1 << 112) * 10);
    }

    function testPriceCumulativeUsesOldReservesBeforeSync() public {
        _addLiquidity(alice, 10 ether, 20 ether);

        vm.warp(block.timestamp + 5);
        token0.transfer(address(pair), 10 ether);
        pair.sync();

        uint256 expectedPrice0FirstPeriod = (uint256(20 ether) << 112) / 10 ether * 5;
        uint256 expectedPrice1FirstPeriod = (uint256(10 ether) << 112) / 20 ether * 5;
        assertEq(pair.price0CumulativeLast(), expectedPrice0FirstPeriod);
        assertEq(pair.price1CumulativeLast(), expectedPrice1FirstPeriod);

        vm.warp(block.timestamp + 5);
        pair.sync();

        uint256 expectedPrice0SecondPeriod = (uint256(20 ether) << 112) / 20 ether * 5;
        uint256 expectedPrice1SecondPeriod = (uint256(20 ether) << 112) / 20 ether * 5;
        assertEq(pair.price0CumulativeLast(), expectedPrice0FirstPeriod + expectedPrice0SecondPeriod);
        assertEq(pair.price1CumulativeLast(), expectedPrice1FirstPeriod + expectedPrice1SecondPeriod);
    }

    function testFeeOffDoesNotMintProtocolLiquidity() public {
        _addLiquidity(alice, 10 ether, 10 ether);
        _swapToken0ForToken1(bob, 1 ether);

        uint256 feeToBalanceBefore = pair.balanceOf(address(0xFEE));
        _addLiquidity(alice, 1 ether, 1 ether);

        assertEq(pair.balanceOf(address(0xFEE)), feeToBalanceBefore);
        assertEq(pair.kLast(), 0);
    }

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
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(pair.kLast(), uint256(r0) * r1);
    }

    function testFeeOnMintsExactProtocolLiquidity() public {
        address feeTo = address(0xFEE);
        factory.setFeeTo(feeTo);

        _addLiquidity(alice, 10 ether, 10 ether);
        uint256 kLastBefore = pair.kLast();

        _swapToken0ForToken1(bob, 1 ether);
        (uint112 reserve0BeforeMintFee, uint112 reserve1BeforeMintFee,) = pair.getReserves();
        uint256 totalSupplyBeforeMintFee = pair.totalSupply();
        uint256 rootK = Math.sqrt(uint256(reserve0BeforeMintFee) * reserve1BeforeMintFee);
        uint256 rootKLast = Math.sqrt(kLastBefore);
        uint256 expectedProtocolLiquidity = totalSupplyBeforeMintFee * (rootK - rootKLast) / (5 * rootK + rootKLast);

        _addLiquidity(alice, 1 ether, 1 ether);

        assertGt(expectedProtocolLiquidity, 0);
        assertEq(pair.balanceOf(feeTo), expectedProtocolLiquidity);
    }

    function testFeeOffClearsKLastAfterBeingEnabled() public {
        factory.setFeeTo(address(0xFEE));
        _addLiquidity(alice, 10 ether, 10 ether);
        assertGt(pair.kLast(), 0);

        factory.setFeeTo(address(0));
        _addLiquidity(alice, 1 ether, 1 ether);

        assertEq(pair.kLast(), 0);
    }

    function testFlashSwapRepaidCallbackSucceeds() public {
        _addLiquidity(alice, 10 ether, 10 ether);
        FlashSwapCallee callee = new FlashSwapCallee();
        token1.transfer(address(callee), 1 ether);

        uint256 amount1Out = 1 ether;
        pair.swap(0, amount1Out, address(callee), abi.encode(address(token0), address(token1)));

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 10 ether);
        assertGt(r1, 10 ether);
        assertEq(token0.balanceOf(address(pair)), r0);
        assertEq(token1.balanceOf(address(pair)), r1);
    }

    function testFlashSwapUnderpaymentRevertsK() public {
        _addLiquidity(alice, 10 ether, 10 ether);
        FlashSwapCallee callee = new FlashSwapCallee();
        callee.setMode(FlashSwapCallee.Mode.Underpay);
        token1.transfer(address(callee), 1 ether);

        vm.expectRevert(bytes("K"));
        pair.swap(0, 1 ether, address(callee), abi.encode(address(token0), address(token1)));
    }

    function testPermitSetsAllowanceWithValidSignature() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(permitOwnerKey, permitOwner, bob, value, deadline);

        pair.permit(permitOwner, bob, value, deadline, v, r, s);

        assertEq(pair.allowance(permitOwner, bob), value);
        assertEq(pair.nonces(permitOwner), 1);
    }

    function testPermitRevertsAfterDeadline() public {
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(permitOwnerKey, permitOwner, bob, 1 ether, deadline);

        vm.warp(deadline + 1);
        vm.expectRevert("permit expired");
        pair.permit(permitOwner, bob, 1 ether, deadline, v, r, s);
    }

    function testPermitRevertsForInvalidSigner() public {
        uint256 wrongKey = 0xB0B;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(wrongKey, permitOwner, bob, 1 ether, deadline);

        vm.expectRevert("invalid signature");
        pair.permit(permitOwner, bob, 1 ether, deadline, v, r, s);
    }

    function testPermitCannotBeReplayed() public {
        uint256 value = 1 ether;
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(permitOwnerKey, permitOwner, bob, value, deadline);

        pair.permit(permitOwner, bob, value, deadline, v, r, s);

        vm.expectRevert("invalid signature");
        pair.permit(permitOwner, bob, value, deadline, v, r, s);
    }

    function _addLiquidity(address provider, uint256 amount0, uint256 amount1) internal returns (uint256 liquidity) {
        vm.startPrank(provider);
        token0.transfer(address(pair), amount0);
        token1.transfer(address(pair), amount1);
        liquidity = pair.mint(provider);
        vm.stopPrank();
    }

    function _swapToken0ForToken1(address trader, uint256 amount0In) internal returns (uint256 amount1Out) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        amount1Out = Library.getAmountOut(amount0In, r0, r1);

        vm.startPrank(trader);
        token0.transfer(address(pair), amount0In);
        pair.swap(0, amount1Out, trader, "");
        vm.stopPrank();
    }

    function _signPermit(uint256 privateKey, address owner_, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(pair.PERMIT_TYPEHASH(), owner_, spender, value, pair.nonces(owner_), deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", pair.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(privateKey, digest);
    }
}
