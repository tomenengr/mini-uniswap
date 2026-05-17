// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DemoTokenFaucet.sol";
import "../src/ERC20.sol";

contract DemoTokenFaucetTest is Test {
    ERC20 tokenA;
    ERC20 tokenB;
    DemoTokenFaucet faucet;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 amountA = 100 ether;
    uint256 amountB = 100 ether;

    function setUp() public {
        tokenA = new ERC20("Demo Token A", "DTA");
        tokenB = new ERC20("Demo Token B", "DTB");
        faucet = new DemoTokenFaucet(address(tokenA), address(tokenB), amountA, amountB);

        tokenA.approve(address(faucet), 10_000 ether);
        tokenB.approve(address(faucet), 10_000 ether);
        faucet.refill(10_000 ether, 10_000 ether);
    }

    function testClaimTransfersBothTokensOnce() public {
        vm.prank(alice);
        faucet.claim();

        assertEq(tokenA.balanceOf(alice), amountA);
        assertEq(tokenB.balanceOf(alice), amountB);
        assertTrue(faucet.claimed(alice));

        vm.prank(alice);
        vm.expectRevert("already claimed");
        faucet.claim();
    }

    function testDifferentWalletsCanClaim() public {
        vm.prank(alice);
        faucet.claim();

        vm.prank(bob);
        faucet.claim();

        assertEq(tokenA.balanceOf(alice), amountA);
        assertEq(tokenB.balanceOf(alice), amountB);
        assertEq(tokenA.balanceOf(bob), amountA);
        assertEq(tokenB.balanceOf(bob), amountB);
    }

    function testOwnerCanUpdateClaimAmounts() public {
        faucet.setClaimAmounts(25 ether, 50 ether);

        vm.prank(alice);
        faucet.claim();

        assertEq(tokenA.balanceOf(alice), 25 ether);
        assertEq(tokenB.balanceOf(alice), 50 ether);
    }

    function testRevertWhenPaused() public {
        faucet.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("paused");
        faucet.claim();
    }

    function testOnlyOwnerCanPauseOrSetAmounts() public {
        vm.prank(alice);
        vm.expectRevert("not owner");
        faucet.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("not owner");
        faucet.setClaimAmounts(1 ether, 1 ether);
    }

    function testOwnerCanWithdraw() public {
        faucet.withdraw(bob, 123 ether, 456 ether);

        assertEq(tokenA.balanceOf(bob), 123 ether);
        assertEq(tokenB.balanceOf(bob), 456 ether);
    }

    function testRefillPullsApprovedTokens() public {
        tokenA.transfer(alice, 5 ether);
        tokenB.transfer(alice, 6 ether);

        vm.startPrank(alice);
        tokenA.approve(address(faucet), 5 ether);
        tokenB.approve(address(faucet), 6 ether);
        faucet.refill(5 ether, 6 ether);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(address(faucet)), 10_005 ether);
        assertEq(tokenB.balanceOf(address(faucet)), 10_006 ether);
    }

    function testConstructorValidation() public {
        vm.expectRevert("zero token");
        new DemoTokenFaucet(address(0), address(tokenB), amountA, amountB);

        vm.expectRevert("same token");
        new DemoTokenFaucet(address(tokenA), address(tokenA), amountA, amountB);

        vm.expectRevert("zero amount");
        new DemoTokenFaucet(address(tokenA), address(tokenB), 0, 0);
    }
}
