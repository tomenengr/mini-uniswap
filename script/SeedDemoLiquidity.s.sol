// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/ERC20.sol";
import "../src/Library.sol";
import "../src/Router.sol";
import "../src/interfaces/IUniswapV2Pair.sol";

contract SeedDemoLiquidity is Script {
    address internal constant FACTORY = 0x0194528124b6c17f6210E17Da8ebC39fE42eF20b;
    address internal constant ROUTER = 0xCd1ee1570826659266F5E1907e1c6A28edbDC245;
    address internal constant TOKEN_A = 0xbBE034a07215bEEb9d430A7d0A769300630EA1D1;
    address internal constant TOKEN_B = 0x952d53e13dd115055b8BeB7EF7a2B70689Ca0622;
    address internal constant PAIR = 0x2487F862d239b779B06Bedf32F98571B9f63f2e3;

    uint256 internal constant DEFAULT_LIQUIDITY_A = 1_000 ether;
    uint256 internal constant DEFAULT_LIQUIDITY_B = 1_000 ether;
    uint256 internal constant DEFAULT_SWAP_IN = 10 ether;

    function run() external {
        uint256 liquidityA = vm.envOr("SEED_LIQUIDITY_A", DEFAULT_LIQUIDITY_A);
        uint256 liquidityB = vm.envOr("SEED_LIQUIDITY_B", DEFAULT_LIQUIDITY_B);
        uint256 swapIn = vm.envOr("SEED_SWAP_IN", DEFAULT_SWAP_IN);

        address deployer = msg.sender;

        require(ERC20(TOKEN_A).balanceOf(deployer) >= liquidityA + swapIn, "insufficient DTA");
        require(ERC20(TOKEN_B).balanceOf(deployer) >= liquidityB, "insufficient DTB");

        console2.log("Seeder:", deployer);
        console2.log("Pair:", PAIR);
        _logReserves("Reserves before:");

        vm.startBroadcast();
        _approveRouter(liquidityA, liquidityB, swapIn);
        (uint256 amountA, uint256 amountB, uint256 liquidity) = _addLiquidity(deployer, liquidityA, liquidityB);
        (uint256 swapAmountIn, uint256 swapAmountOut) = _swapDtaForDtb(deployer, swapIn);
        vm.stopBroadcast();

        console2.log("Liquidity added:");
        console2.log("  DTA:", amountA);
        console2.log("  DTB:", amountB);
        console2.log("  LP:", liquidity);
        console2.log("Swap executed:");
        console2.log("  DTA in:", swapAmountIn);
        console2.log("  DTB out:", swapAmountOut);
        _logReserves("Reserves after:");
    }

    function _approveRouter(uint256 liquidityA, uint256 liquidityB, uint256 swapIn) internal {
        require(ERC20(TOKEN_A).approve(ROUTER, liquidityA + swapIn), "approve DTA failed");
        require(ERC20(TOKEN_B).approve(ROUTER, liquidityB), "approve DTB failed");
    }

    function _addLiquidity(address deployer, uint256 liquidityA, uint256 liquidityB)
        internal
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        return Router(payable(ROUTER))
            .addLiquidity(TOKEN_A, TOKEN_B, liquidityA, liquidityB, 0, 0, deployer, block.timestamp + 30 minutes);
    }

    function _swapDtaForDtb(address deployer, uint256 swapIn)
        internal
        returns (uint256 swapAmountIn, uint256 swapAmountOut)
    {
        address[] memory path = new address[](2);
        path[0] = TOKEN_A;
        path[1] = TOKEN_B;

        uint256[] memory quotedAmounts = Library.getAmountsOut(FACTORY, swapIn, path);
        uint256 amountOutMin = quotedAmounts[1] * 99 / 100;
        uint256[] memory swapAmounts = Router(payable(ROUTER))
            .swapExactTokensForTokens(swapIn, amountOutMin, path, deployer, block.timestamp + 30 minutes);

        return (swapAmounts[0], swapAmounts[1]);
    }

    function _logReserves(string memory label) internal view {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(PAIR).getReserves();
        console2.log(label);
        console2.log("  reserve0:", uint256(reserve0));
        console2.log("  reserve1:", uint256(reserve1));
    }
}
