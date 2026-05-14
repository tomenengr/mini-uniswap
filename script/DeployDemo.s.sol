// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../src/ERC20.sol";
import "../src/Factory.sol";
import "../src/Router.sol";
import "../src/SimpleTwapOracle.sol";

contract DemoWETH is ERC20("Wrapped Ether", "WETH") {
    constructor() {
        _burn(msg.sender, totalSupply);
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        require(balanceOf[msg.sender] >= wad, "not enough");
        balanceOf[msg.sender] -= wad;
        totalSupply -= wad;
        emit Transfer(msg.sender, address(0), wad);
        (bool success,) = msg.sender.call{value: wad}("");
        require(success, "ETH_TRANSFER_FAILED");
    }
}

contract DeployDemo is Script {
    function run() external {
        vm.startBroadcast();

        Factory factory = new Factory(msg.sender);
        DemoWETH weth = new DemoWETH();
        Router router = new Router(address(factory), address(weth));
        ERC20 tokenA = new ERC20("Demo Token A", "DTA");
        ERC20 tokenB = new ERC20("Demo Token B", "DTB");

        address pair = factory.createPair(address(tokenA), address(tokenB));
        SimpleTwapOracle oracle = new SimpleTwapOracle(pair, 10 minutes);

        vm.stopBroadcast();

        console2.log("Factory:", address(factory));
        console2.log("WETH:", address(weth));
        console2.log("Router:", address(router));
        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));
        console2.log("Pair:", pair);
        console2.log("SimpleTwapOracle:", address(oracle));
    }
}
