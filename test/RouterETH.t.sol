// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/ERC20.sol";
import "../src/Factory.sol";
import "../src/Library.sol";
import "../src/Pair.sol";
import "../src/Router.sol";
import "./Mocks.t.sol";

contract RouterETHTest is Test {
    Factory factory;
    Router router;
    ERC20 token;
    MockWETH weth;

    address alice = address(0x1);

    function setUp() public {
        factory = new Factory(address(this));
        weth = new MockWETH();
        router = new Router(address(factory), address(weth));
        token = new ERC20("Token", "TKN");

        token.transfer(alice, 1000 ether);
        vm.deal(alice, 100 ether);
    }

    function testAddLiquidityETHCreatesPairAndMintsLp() public {
        vm.startPrank(alice);
        token.approve(address(router), 10 ether);
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) =
            router.addLiquidityETH{value: 5 ether}(address(token), 10 ether, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        address pairAddress = factory.getPair(address(token), address(weth));
        Pair pair = Pair(pairAddress);

        assertTrue(pairAddress != address(0));
        assertEq(amountToken, 10 ether);
        assertEq(amountETH, 5 ether);
        assertEq(liquidity, 7071067811865474244);
        assertEq(pair.balanceOf(alice), liquidity);
        _assertPairReserves(pair, address(token), 10 ether, address(weth), 5 ether);
        assertEq(weth.balanceOf(pairAddress), 5 ether);
    }

    function testAddLiquidityETHRefundsExcessETH() public {
        _addLiquidityETH(alice, 10 ether, 5 ether);
        uint256 balanceBefore = alice.balance;

        vm.startPrank(alice);
        token.approve(address(router), 10 ether);
        (uint256 amountToken, uint256 amountETH,) =
            router.addLiquidityETH{value: 10 ether}(address(token), 10 ether, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertEq(amountToken, 10 ether);
        assertEq(amountETH, 5 ether);
        assertEq(alice.balance, balanceBefore - 5 ether);
    }

    function testRevertWhenAddLiquidityETHBelowTokenMinimum() public {
        _addLiquidityETH(alice, 10 ether, 5 ether);

        vm.startPrank(alice);
        token.approve(address(router), 100 ether);
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        router.addLiquidityETH{value: 1 ether}(address(token), 100 ether, 3 ether, 0, alice, block.timestamp);
        vm.stopPrank();
    }

    function testRevertWhenAddLiquidityETHBelowETHMinimum() public {
        _addLiquidityETH(alice, 10 ether, 5 ether);

        vm.startPrank(alice);
        token.approve(address(router), 10 ether);
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_B_AMOUNT");
        router.addLiquidityETH{value: 10 ether}(address(token), 10 ether, 0, 6 ether, alice, block.timestamp);
        vm.stopPrank();
    }

    function testRemoveLiquidityETHUnwrapsWETHToETH() public {
        (,, uint256 liquidity) = _addLiquidityETH(alice, 10 ether, 5 ether);
        Pair pair = Pair(factory.getPair(address(token), address(weth)));

        uint256 tokenBefore = token.balanceOf(alice);
        uint256 ethBefore = alice.balance;
        uint256 totalSupplyBefore = pair.totalSupply();
        uint256 expectedToken = liquidity * token.balanceOf(address(pair)) / totalSupplyBefore;
        uint256 expectedETH = liquidity * weth.balanceOf(address(pair)) / totalSupplyBefore;

        vm.startPrank(alice);
        pair.approve(address(router), liquidity);
        (uint256 amountToken, uint256 amountETH) =
            router.removeLiquidityETH(address(token), liquidity, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertEq(amountToken, expectedToken);
        assertEq(amountETH, expectedETH);
        assertEq(token.balanceOf(alice), tokenBefore + amountToken);
        assertEq(alice.balance, ethBefore + amountETH);
        assertEq(pair.balanceOf(alice), 0);
    }

    function testRevertWhenRemoveLiquidityETHBelowTokenMinimum() public {
        (,, uint256 liquidity) = _addLiquidityETH(alice, 10 ether, 5 ether);
        Pair pair = Pair(factory.getPair(address(token), address(weth)));

        vm.startPrank(alice);
        pair.approve(address(router), liquidity);
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_TOKEN_AMOUNT");
        router.removeLiquidityETH(address(token), liquidity, 10 ether, 0, alice, block.timestamp);
        vm.stopPrank();
    }

    function testRevertWhenRemoveLiquidityETHBelowETHMinimum() public {
        (,, uint256 liquidity) = _addLiquidityETH(alice, 10 ether, 5 ether);
        Pair pair = Pair(factory.getPair(address(token), address(weth)));

        vm.startPrank(alice);
        pair.approve(address(router), liquidity);
        vm.expectRevert("UniswapV2Router: INSUFFICIENT_ETH_AMOUNT");
        router.removeLiquidityETH(address(token), liquidity, 0, 5 ether, alice, block.timestamp);
        vm.stopPrank();
    }

    function testRouterReceiveOnlyAcceptsWETH() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success, bytes memory reason) = address(router).call{value: 1 ether}("");

        assertFalse(success);
        assertEq(_revertString(reason), "only WETH");
    }

    function _addLiquidityETH(address provider, uint256 amountToken, uint256 msgValue)
        internal
        returns (uint256 actualToken, uint256 actualETH, uint256 liquidity)
    {
        vm.startPrank(provider);
        token.approve(address(router), amountToken);
        (actualToken, actualETH, liquidity) =
            router.addLiquidityETH{value: msgValue}(address(token), amountToken, 0, 0, provider, block.timestamp);
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

    function _revertString(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 68) return "";
        assembly {
            revertData := add(revertData, 0x04)
        }
        return abi.decode(revertData, (string));
    }
}
