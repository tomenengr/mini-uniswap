// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/ERC20.sol";
import "../src/Factory.sol";
import "../src/Library.sol";
import "../src/Pair.sol";
import "../src/Router.sol";

contract RouterTest is Test {
    Factory factory;
    Router router;
    ERC20 tokenA;
    ERC20 tokenB;
    ERC20 tokenC;

    address alice = address(0x1);
    address bob = address(0x2);
    address weth = address(0xBEEF);

    function setUp() public {
        factory = new Factory(address(this));
        router = new Router(address(factory), weth);

        tokenA = new ERC20("Token A", "A");
        tokenB = new ERC20("Token B", "B");
        tokenC = new ERC20("Token C", "C");

        tokenA.transfer(alice, 1000 ether);
        tokenB.transfer(alice, 1000 ether);
        tokenC.transfer(alice, 1000 ether);
        tokenA.transfer(bob, 1000 ether);
        tokenB.transfer(bob, 1000 ether);
        tokenC.transfer(bob, 1000 ether);
    }

    function testAddLiquidityCreatesPairAndMintsLp() public {
        vm.startPrank(alice);
        tokenA.approve(address(router), 10 ether);
        tokenB.approve(address(router), 10 ether);

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            router.addLiquidity(address(tokenA), address(tokenB), 10 ether, 10 ether, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        Pair pair = Pair(pairAddress);

        assertTrue(pairAddress != address(0));
        assertEq(amountA, 10 ether);
        assertEq(amountB, 10 ether);
        assertEq(liquidity, 10 ether - pair.MINIMUM_LIQUIDITY());
        assertEq(pair.balanceOf(alice), liquidity);

        _assertPairReserves(pair, address(tokenA), 10 ether, address(tokenB), 10 ether);
    }

    function testAddLiquidityUsesOptimalRatio() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 20 ether);

        vm.startPrank(alice);
        tokenA.approve(address(router), 10 ether);
        tokenB.approve(address(router), 50 ether);

        (uint256 amountA, uint256 amountB,) =
            router.addLiquidity(address(tokenA), address(tokenB), 10 ether, 50 ether, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertEq(amountA, 10 ether);
        assertEq(amountB, 20 ether);
    }

    function testRevertWhenAddLiquidityExpired() public {
        vm.warp(100);

        vm.startPrank(alice);
        tokenA.approve(address(router), 10 ether);
        tokenB.approve(address(router), 10 ether);

        vm.expectRevert("expired");
        router.addLiquidity(address(tokenA), address(tokenB), 10 ether, 10 ether, 0, 0, alice, 99);
        vm.stopPrank();
    }

    function testRevertWhenAddLiquidityBelowMinimumAmount() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 20 ether);

        vm.startPrank(alice);
        tokenA.approve(address(router), 10 ether);
        tokenB.approve(address(router), 50 ether);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_B_AMOUNT");
        router.addLiquidity(address(tokenA), address(tokenB), 10 ether, 50 ether, 0, 21 ether, alice, block.timestamp);
        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        (,, uint256 liquidity) = _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        Pair pair = Pair(factory.getPair(address(tokenA), address(tokenB)));

        uint256 balanceABefore = tokenA.balanceOf(alice);
        uint256 balanceBBefore = tokenB.balanceOf(alice);

        vm.startPrank(alice);
        pair.approve(address(router), liquidity);
        (uint256 amountA, uint256 amountB) =
            router.removeLiquidity(address(tokenA), address(tokenB), liquidity, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertEq(amountA, 10 ether - pair.MINIMUM_LIQUIDITY());
        assertEq(amountB, 10 ether - pair.MINIMUM_LIQUIDITY());
        assertEq(tokenA.balanceOf(alice), balanceABefore + amountA);
        assertEq(tokenB.balanceOf(alice), balanceBBefore + amountB);
        assertEq(pair.balanceOf(alice), 0);
    }

    function testRevertWhenRemoveLiquidityBelowMinimumAmount() public {
        (,, uint256 liquidity) = _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        Pair pair = Pair(factory.getPair(address(tokenA), address(tokenB)));

        vm.startPrank(alice);
        pair.approve(address(router), liquidity);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        router.removeLiquidity(address(tokenA), address(tokenB), liquidity, 10 ether, 0, alice, block.timestamp);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokens() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        uint256 expectedOut = Library.getAmountOut(1 ether, 10 ether, 10 ether);

        vm.startPrank(bob);
        tokenA.approve(address(router), 1 ether);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(1 ether, expectedOut, _path(tokenA, tokenB), bob, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], 1 ether);
        assertEq(amounts[1], expectedOut);
        assertEq(tokenB.balanceOf(bob), 1000 ether + expectedOut);
    }

    function testRevertWhenSwapExactTokensOutputIsTooLow() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        uint256 expectedOut = Library.getAmountOut(1 ether, 10 ether, 10 ether);

        vm.startPrank(bob);
        tokenA.approve(address(router), 1 ether);

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForTokens(1 ether, expectedOut + 1, _path(tokenA, tokenB), bob, block.timestamp);
        vm.stopPrank();
    }

    function testSwapTokensForExactTokens() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        uint256 amountIn = Library.getAmountIn(1 ether, 10 ether, 10 ether);

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);
        uint256[] memory amounts =
            router.swapTokensForExactTokens(1 ether, amountIn, _path(tokenA, tokenB), bob, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], amountIn);
        assertEq(amounts[1], 1 ether);
        assertEq(tokenA.balanceOf(bob), 1000 ether - amountIn);
        assertEq(tokenB.balanceOf(bob), 1001 ether);
    }

    function testRevertWhenSwapTokensForExactTokensInputIsTooHigh() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        uint256 amountIn = Library.getAmountIn(1 ether, 10 ether, 10 ether);

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);

        vm.expectRevert("UniswapV2Router: EXCESSIVE_INPUT_AMOUNT");
        router.swapTokensForExactTokens(1 ether, amountIn - 1, _path(tokenA, tokenB), bob, block.timestamp);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensMultiHop() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        _addLiquidity(alice, tokenB, tokenC, 10 ether, 20 ether);

        uint256 expectedB = Library.getAmountOut(1 ether, 10 ether, 10 ether);
        uint256 expectedC = Library.getAmountOut(expectedB, 10 ether, 20 ether);

        vm.startPrank(bob);
        tokenA.approve(address(router), 1 ether);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(1 ether, expectedC, _path(tokenA, tokenB, tokenC), bob, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], 1 ether);
        assertEq(amounts[1], expectedB);
        assertEq(amounts[2], expectedC);
        assertEq(tokenC.balanceOf(bob), 1000 ether + expectedC);
    }

    function testFuzzSwapExactTokensForTokensSingleHop(uint256 amountIn) public {
        _addLiquidity(alice, tokenA, tokenB, 100 ether, 100 ether);
        amountIn = bound(amountIn, 1e9, 10 ether);

        uint256[] memory expectedAmounts = Library.getAmountsOut(address(factory), amountIn, _path(tokenA, tokenB));
        uint256 bobBalanceBefore = tokenB.balanceOf(bob);

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, expectedAmounts[1], _path(tokenA, tokenB), bob, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(tokenB.balanceOf(bob), bobBalanceBefore + expectedAmounts[1]);
        _assertPairReserves(
            Pair(factory.getPair(address(tokenA), address(tokenB))),
            address(tokenA),
            100 ether + amountIn,
            address(tokenB),
            100 ether - expectedAmounts[1]
        );
    }

    function testFuzzSwapExactTokensForTokensMultiHop(uint256 amountIn) public {
        _addLiquidity(alice, tokenA, tokenB, 100 ether, 200 ether);
        _addLiquidity(alice, tokenB, tokenC, 200 ether, 100 ether);
        amountIn = bound(amountIn, 1e9, 10 ether);

        address[] memory path = _path(tokenA, tokenB, tokenC);
        uint256[] memory expectedAmounts = Library.getAmountsOut(address(factory), amountIn, path);
        uint256 bobBalanceBefore = tokenC.balanceOf(bob);

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);
        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, expectedAmounts[2], path, bob, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);
        assertEq(tokenC.balanceOf(bob), bobBalanceBefore + expectedAmounts[2]);
    }

    function testFuzzSwapTokensForExactTokensMultiHop(uint256 amountOut) public {
        _addLiquidity(alice, tokenA, tokenB, 100 ether, 200 ether);
        _addLiquidity(alice, tokenB, tokenC, 200 ether, 100 ether);
        amountOut = bound(amountOut, 1, 10 ether);

        address[] memory path = _path(tokenA, tokenB, tokenC);
        uint256[] memory expectedAmounts = Library.getAmountsIn(address(factory), amountOut, path);
        uint256 bobTokenABefore = tokenA.balanceOf(bob);
        uint256 bobTokenCBefore = tokenC.balanceOf(bob);

        vm.startPrank(bob);
        tokenA.approve(address(router), expectedAmounts[0]);
        uint256[] memory amounts =
            router.swapTokensForExactTokens(amountOut, expectedAmounts[0], path, bob, block.timestamp);
        vm.stopPrank();

        assertEq(amounts[0], expectedAmounts[0]);
        assertEq(amounts[1], expectedAmounts[1]);
        assertEq(amounts[2], expectedAmounts[2]);
        assertEq(tokenA.balanceOf(bob), bobTokenABefore - expectedAmounts[0]);
        assertEq(tokenC.balanceOf(bob), bobTokenCBefore + amountOut);
    }

    function testRevertWhenSwapExpired() public {
        _addLiquidity(alice, tokenA, tokenB, 10 ether, 10 ether);
        vm.warp(100);

        vm.startPrank(bob);
        tokenA.approve(address(router), 1 ether);

        vm.expectRevert("expired");
        router.swapExactTokensForTokens(1 ether, 0, _path(tokenA, tokenB), bob, 99);
        vm.stopPrank();
    }

    function _addLiquidity(address provider, ERC20 tokenX, ERC20 tokenY, uint256 amountX, uint256 amountY)
        internal
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        vm.startPrank(provider);
        tokenX.approve(address(router), amountX);
        tokenY.approve(address(router), amountY);
        (amountA, amountB, liquidity) =
            router.addLiquidity(address(tokenX), address(tokenY), amountX, amountY, 0, 0, provider, block.timestamp);
        vm.stopPrank();
    }

    function _assertPairReserves(Pair pair, address tokenX, uint256 reserveX, address tokenY, uint256 reserveY)
        internal
        view
    {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        if (pair.token0() == tokenX) {
            assertEq(reserve0, reserveX);
            assertEq(reserve1, reserveY);
        } else {
            assertEq(pair.token0(), tokenY);
            assertEq(reserve0, reserveY);
            assertEq(reserve1, reserveX);
        }
    }

    function _path(ERC20 tokenX, ERC20 tokenY) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(tokenX);
        path[1] = address(tokenY);
    }

    function _path(ERC20 tokenX, ERC20 tokenY, ERC20 tokenZ) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = address(tokenX);
        path[1] = address(tokenY);
        path[2] = address(tokenZ);
    }
}
