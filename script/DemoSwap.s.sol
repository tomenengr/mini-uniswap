// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/ERC20.sol";
import "../src/Library.sol";
import "../src/Router.sol";
import "../src/interfaces/IUniswapV2Pair.sol";

contract DemoSwap is Script {
    address internal constant FACTORY = 0x0194528124b6c17f6210E17Da8ebC39fE42eF20b;
    address internal constant ROUTER = 0xCd1ee1570826659266F5E1907e1c6A28edbDC245;
    address internal constant TOKEN_A = 0xbBE034a07215bEEb9d430A7d0A769300630EA1D1;
    address internal constant TOKEN_B = 0x952d53e13dd115055b8BeB7EF7a2B70689Ca0622;
    address internal constant PAIR = 0x2487F862d239b779B06Bedf32F98571B9f63f2e3;

    uint256 internal constant DEFAULT_SWAP_IN = 10 ether;
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 100;
    uint256 internal constant BPS = 10_000;

    function run() external {
        uint256 swapIn = vm.envOr("DEMO_SWAP_IN", DEFAULT_SWAP_IN);
        uint256 slippageBps = vm.envOr("DEMO_SWAP_SLIPPAGE_BPS", DEFAULT_SLIPPAGE_BPS);
        require(slippageBps < BPS, "invalid slippage");

        address trader = msg.sender;
        require(ERC20(TOKEN_A).balanceOf(trader) >= swapIn, "insufficient DTA");

        address[] memory path = _path();
        uint256 quotedOut = Library.getAmountsOut(FACTORY, swapIn, path)[1];
        uint256 amountOutMin = quotedOut * (BPS - slippageBps) / BPS;

        console2.log("Trader:", trader);
        console2.log("Pair:", PAIR);
        console2.log("DTA in:", swapIn);
        console2.log("Quoted DTB out:", quotedOut);
        console2.log("Min DTB out:", amountOutMin);
        _logReserves("Reserves before:");

        vm.startBroadcast();
        require(ERC20(TOKEN_A).approve(ROUTER, swapIn), "approve DTA failed");
        uint256[] memory amounts = Router(payable(ROUTER))
            .swapExactTokensForTokens(swapIn, amountOutMin, path, trader, block.timestamp + 30 minutes);
        vm.stopBroadcast();

        console2.log("Swap executed:");
        console2.log("  DTA in:", amounts[0]);
        console2.log("  DTB out:", amounts[1]);
        _logReserves("Reserves after:");
    }

    function _path() internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = TOKEN_A;
        path[1] = TOKEN_B;
    }

    function _logReserves(string memory label) internal view {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(PAIR).getReserves();
        console2.log(label);
        console2.log("  reserve0:", uint256(reserve0));
        console2.log("  reserve1:", uint256(reserve1));
    }
}
