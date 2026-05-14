// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Library.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/ERC20.sol";

contract LibraryHarness {
    function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1) {
        return Library.sortTokens(tokenA, tokenB);
    }

    function quote(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return Library.quote(amountIn, reserveIn, reserveOut);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory)
    {
        return Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        external
        view
        returns (uint256[] memory)
    {
        return Library.getAmountsIn(factory, amountOut, path);
    }
}

contract LibraryTest is Test {
    LibraryHarness harness;
    Factory factory;
    ERC20 tokenA;
    ERC20 tokenB;
    ERC20 tokenC;

    function setUp() public {
        harness = new LibraryHarness();
        factory = new Factory(address(this));

        tokenA = new ERC20("Token A", "A");
        tokenB = new ERC20("Token B", "B");
        tokenC = new ERC20("Token C", "C");
    }

    function testSortTokens() public view {
        (address token0, address token1) = harness.sortTokens(address(tokenA), address(tokenB));
        assertTrue(token0 < token1);
        assertTrue(token0 == address(tokenA) || token0 == address(tokenB));
        assertTrue(token1 == address(tokenA) || token1 == address(tokenB));
    }

    function testRevertWhenSortTokensIdentical() public {
        vm.expectRevert("identical tokens");
        harness.sortTokens(address(tokenA), address(tokenA));
    }

    function testRevertWhenSortTokensZeroAddress() public {
        vm.expectRevert("token0 address(0)");
        harness.sortTokens(address(0), address(tokenA));
    }

    function testQuote() public view {
        uint256 amountOut = harness.quote(100 ether, 1000 ether, 2000 ether);
        assertEq(amountOut, 200 ether);
    }

    function testFuzzQuoteMatchesFormula(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view {
        amountIn = bound(amountIn, 1, 1e30);
        reserveIn = bound(reserveIn, 1, 1e30);
        reserveOut = bound(reserveOut, 1, 1e30);

        uint256 amountOut = harness.quote(amountIn, reserveIn, reserveOut);

        assertEq(amountOut, amountIn * reserveOut / reserveIn);
    }

    function testRevertWhenQuoteAmountIsZero() public {
        vm.expectRevert("invalid input");
        harness.quote(0, 1_000 ether, 2_000 ether);
    }

    function testRevertWhenQuoteReserveIsZero() public {
        vm.expectRevert("not enough");
        harness.quote(100 ether, 0, 2_000 ether);

        vm.expectRevert("not enough");
        harness.quote(100 ether, 1_000 ether, 0);
    }

    function testGetAmountOut() public view {
        uint256 amountOut = harness.getAmountOut(100 ether, 1000 ether, 1000 ether);
        uint256 numerator = 100 ether * 997 * 1000 ether;
        uint256 denominator = 1000 ether * 1000 + 100 ether * 997;
        uint256 expected = numerator / denominator;
        assertEq(amountOut, expected);
    }

    function testFuzzGetAmountOutMatchesFormula(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public view {
        amountIn = bound(amountIn, 1, 1e30);
        reserveIn = bound(reserveIn, 1, 1e30);
        reserveOut = bound(reserveOut, 1, 1e30);

        uint256 amountOut = harness.getAmountOut(amountIn, reserveIn, reserveOut);
        uint256 expected = amountIn * 997 * reserveOut / (reserveIn * 1000 + amountIn * 997);

        assertEq(amountOut, expected);
        assertLt(amountOut, reserveOut);
    }

    function testRevertWhenGetAmountOutAmountIsZero() public {
        vm.expectRevert("invalid input");
        harness.getAmountOut(0, 1_000 ether, 1_000 ether);
    }

    function testRevertWhenGetAmountOutReserveIsZero() public {
        vm.expectRevert("not enough");
        harness.getAmountOut(100 ether, 0, 1_000 ether);

        vm.expectRevert("not enough");
        harness.getAmountOut(100 ether, 1_000 ether, 0);
    }

    function testGetAmountIn() public view {
        uint256 amountIn = harness.getAmountIn(100 ether, 1000 ether, 1000 ether);
        uint256 numerator = 100 ether * 1000 ether * 1000;
        uint256 denominactor = (1000 ether - 100 ether) * 997;
        uint256 expected = numerator / denominactor + 1;
        assertEq(amountIn, expected);
    }

    function testFuzzGetAmountInProducesEnoughOutput(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        view
    {
        reserveIn = bound(reserveIn, 1, 1e22);
        reserveOut = bound(reserveOut, 2, 1e22);
        amountOut = bound(amountOut, 1, reserveOut - 1);

        uint256 amountIn = harness.getAmountIn(amountOut, reserveIn, reserveOut);
        uint256 actualOut = harness.getAmountOut(amountIn, reserveIn, reserveOut);

        assertGe(actualOut, amountOut);
    }

    function testRevertWhenGetAmountInAmountIsZero() public {
        vm.expectRevert("invalid input");
        harness.getAmountIn(0, 1000 ether, 1000 ether);
    }

    function testRevertWhenGetAmountInReserveIsZero() public {
        vm.expectRevert("not enough");
        harness.getAmountIn(100 ether, 0, 1_000 ether);

        vm.expectRevert("not enough");
        harness.getAmountIn(100 ether, 1_000 ether, 0);
    }

    function testGetAmountsOut() public {
        _createPairWithLiquidity(tokenA, tokenB, 1_000 ether, 1_000 ether);
        _createPairWithLiquidity(tokenB, tokenC, 1_000 ether, 2_000 ether);
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory amounts = harness.getAmountsOut(address(factory), 100 ether, path);
        assertEq(amounts.length, 3);
        assertEq(amounts[0], 100 ether);

        uint256 expectedB = harness.getAmountOut(100 ether, 1000 ether, 1000 ether);
        uint256 expectedC = harness.getAmountOut(expectedB, 1000 ether, 2000 ether);

        assertEq(amounts[1], expectedB);
        assertEq(amounts[2], expectedC);
    }

    function testGetAmountsIn() public {
        _createPairWithLiquidity(tokenA, tokenB, 1_000 ether, 1_000 ether);
        _createPairWithLiquidity(tokenB, tokenC, 1_000 ether, 2_000 ether);

        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory amounts = harness.getAmountsIn(address(factory), 100 ether, path);

        assertEq(amounts.length, 3);
        assertEq(amounts[2], 100 ether);

        uint256 expectedB = harness.getAmountIn(100 ether, 1000 ether, 2000 ether);
        uint256 expectedC = harness.getAmountIn(expectedB, 1000 ether, 1000 ether);

        assertEq(expectedB, amounts[1]);
        assertEq(expectedC, amounts[0]);
    }

    function testRevertWhenGetAmountsOutPathIsInvalid() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        vm.expectRevert("invalid path");
        harness.getAmountsOut(address(factory), 100 ether, path);
    }

    function testRevertWhenGetAmountsInPathIsInvalid() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenA);

        vm.expectRevert("invalid path");
        harness.getAmountsIn(address(factory), 100 ether, path);
    }

    function _createPairWithLiquidity(ERC20 tokenX, ERC20 tokenY, uint256 amountX, uint256 amountY) internal {
        address pair = factory.createPair(address(tokenX), address(tokenY));

        tokenX.transfer(pair, amountX);
        tokenY.transfer(pair, amountY);

        Pair(pair).mint(address(this));
    }
}
