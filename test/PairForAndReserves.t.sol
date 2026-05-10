//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/Library.sol";
import "../src/ERC20.sol";

contract LibraryHarness {
    function pairFor(address factory, address tokenA, address tokenB) external pure returns (address) {
        return Library.pairFor(factory, tokenA, tokenB);
    }

    function getReserves(address factory, address tokenA, address tokenB)
        external
        view
        returns (uint112 reserveA, uint112 reserveB)
    {
        return Library.getReserves(factory, tokenA, tokenB);
    }
}

contract PairForAndReservesTest is Test {
    Factory factory;
    ERC20 tokenA;
    ERC20 tokenB;
    LibraryHarness harness;

    function setUp() public {
        harness = new LibraryHarness();
        factory = new Factory(address(this));
        tokenA = new ERC20("TokenA", "TKA");
        tokenB = new ERC20("TokenB", "TKB");
    }

    function testPairForMatchesCreate2() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        address computed = harness.pairFor(address(factory), address(tokenA), address(tokenB));
        assertEq(computed, pair, "pairFor mismatch");
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair, "factory getPair mismatch");
    }

    function testGetReservesOrder() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));

        uint256 amountA = 10_000 ether;
        uint256 amountB = 20_000 ether;
        tokenA.transfer(pair, amountA);
        tokenB.transfer(pair, amountB);
        Pair(pair).mint(address(this));

        (uint112 rA, uint112 rB) = harness.getReserves(address(factory), address(tokenA), address(tokenB));
        (uint112 r0, uint112 r1,) = Pair(pair).getReserves();
        address token0 = Pair(pair).token0();

        if (token0 == address(tokenA)) {
            assertEq(rA, r0, "reserveA should map to reserve0");
            assertEq(rB, r1, "reserveB should map to reserve1");
        } else {
            assertEq(rA, r1, "reserveA should map to reserve1");
            assertEq(rB, r0, "reserveB should map to reserve0");
        }

        assertGt(uint256(rA), 0);
        assertGt(uint256(rB), 0);
    }
}

