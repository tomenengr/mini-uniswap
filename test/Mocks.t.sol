// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/ERC20.sol";
import "../src/interfaces/IUniswapV2Callee.sol";

contract MockWETH is ERC20("Wrapped Ether", "WETH") {
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

contract FlashSwapCallee is IUniswapV2Callee {
    enum Mode {
        Repay,
        Underpay,
        DoNothing
    }

    Mode public mode;

    function setMode(Mode _mode) external {
        mode = _mode;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        (address token0, address token1) = abi.decode(data, (address, address));

        if (mode == Mode.DoNothing) return;

        if (amount0 > 0) {
            uint256 repay0 = mode == Mode.Underpay ? amount0 : amount0 * 1004 / 1000 + 1;
            ERC20(token0).transfer(msg.sender, repay0);
        }

        if (amount1 > 0) {
            uint256 repay1 = mode == Mode.Underpay ? amount1 : amount1 * 1004 / 1000 + 1;
            ERC20(token1).transfer(msg.sender, repay1);
        }
    }
}
