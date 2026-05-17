// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/DemoTokenFaucet.sol";

contract DeployDemoTokenFaucet is Script {
    address internal constant DEFAULT_DTA = 0xbBE034a07215bEEb9d430A7d0A769300630EA1D1;
    address internal constant DEFAULT_DTB = 0x952d53e13dd115055b8BeB7EF7a2B70689Ca0622;
    uint256 internal constant DEFAULT_CLAIM_AMOUNT = 100 ether;

    function run() external {
        address tokenA = vm.envOr("DTA_ADDRESS", DEFAULT_DTA);
        address tokenB = vm.envOr("DTB_ADDRESS", DEFAULT_DTB);
        uint256 amountA = vm.envOr("FAUCET_AMOUNT_A", DEFAULT_CLAIM_AMOUNT);
        uint256 amountB = vm.envOr("FAUCET_AMOUNT_B", DEFAULT_CLAIM_AMOUNT);

        vm.startBroadcast();
        DemoTokenFaucet faucet = new DemoTokenFaucet(tokenA, tokenB, amountA, amountB);
        vm.stopBroadcast();

        console2.log("DemoTokenFaucet:", address(faucet));
        console2.log("TokenA:", tokenA);
        console2.log("TokenB:", tokenB);
        console2.log("AmountA:", amountA);
        console2.log("AmountB:", amountB);
    }
}
