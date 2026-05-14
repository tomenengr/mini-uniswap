// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/ERC20.sol";
import "../src/Factory.sol";
import "../src/Pair.sol";
import "../src/SimpleTwapOracle.sol";

contract SimpleTwapOracleTest is Test {
    Factory factory;
    Pair pair;
    ERC20 token0;
    ERC20 token1;
    SimpleTwapOracle oracle;

    function setUp() public {
        factory = new Factory(address(this));
        ERC20 tokenA = new ERC20("Token A", "A");
        ERC20 tokenB = new ERC20("Token B", "B");
        pair = Pair(factory.createPair(address(tokenA), address(tokenB)));
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        token0.transfer(address(pair), 10 ether);
        token1.transfer(address(pair), 20 ether);
        pair.mint(address(this));

        oracle = new SimpleTwapOracle(address(pair), 10);
    }

    function testUpdateStoresAveragePriceAfterPeriod() public {
        vm.warp(block.timestamp + 10);
        oracle.update();

        assertEq(oracle.consult(address(token0), 1 ether), 2 ether);
        assertEq(oracle.consult(address(token1), 2 ether), 1 ether);
    }

    function testRevertWhenUpdateBeforePeriodElapsed() public {
        vm.warp(block.timestamp + 9);
        vm.expectRevert("period not elapsed");
        oracle.update();
    }

    function testRevertWhenConsultBeforeUpdate() public {
        vm.expectRevert("missing average");
        oracle.consult(address(token0), 1 ether);
    }

    function testRevertWhenConsultInvalidToken() public {
        vm.warp(block.timestamp + 10);
        oracle.update();

        vm.expectRevert("invalid token");
        oracle.consult(address(0xBEEF), 1 ether);
    }
}
