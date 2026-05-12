// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/ERC20.sol";

contract FactoryTest is Test {
    Factory factory;
    ERC20 tokenA;
    ERC20 tokenB;

    function setUp() public {
        factory = new Factory(address(this));
        tokenA = new ERC20("TOKEN A", "A");
        tokenB = new ERC20("TOKEN B", "B");
    }

    function testCreatePair() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
        assertEq(factory.allPairsLength(), 1);

        address token0 = Pair(pair).token0();
        address token1 = Pair(pair).token1();
        assertTrue(token0 < token1);
    }

    function testRevertWhenIdenticalTokens() public {
        vm.expectRevert("same coin");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testRevertWhenZeroAddress() public {
        vm.expectRevert("address(0)");
        factory.createPair(address(0), address(tokenA));
    }

    function testRevertWhenDuplicatePair() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert("duplicate");
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testRevertWhenDuplicatePairWithReverseOrder() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert("duplicate");
        factory.createPair(address(tokenB), address(tokenA));
    }

    function testCreatePairOrderDoesNotMatter() public {
        address pair = factory.createPair(address(tokenB), address(tokenA));

        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);

        assertEq(Pair(pair).token0(), address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB));
        assertEq(Pair(pair).token1(), address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA));
    }

    function testInitialFeeConfig() public view {
        assertEq(factory.feeTo(), address(0));
        assertEq(factory.feeToSetter(), address(this));
    }

    function testSetFeeTo() public {
        address feeTo = address(0xBEEF);

        factory.setFeeTo(feeTo);

        assertEq(factory.feeTo(), feeTo);
    }

    function testRevertWhenNonSetterSetsFeeTo() public {
        address alice = address(0x1);

        vm.prank(alice);
        vm.expectRevert("forbidden");
        factory.setFeeTo(address(0xBEEF));
    }

    function testSetFeeToSetter() public {
        address alice = address(0x1);
        address bob = address(0x2);

        vm.prank(alice);
        vm.expectRevert("forbidden");
        factory.setFeeToSetter(bob);

        factory.setFeeToSetter(bob);

        assertEq(factory.feeToSetter(), bob);
    }
}
