//SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import "./interfaces/IUniswapV2Pair.sol";
import "./Pair.sol";

library Library {
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "identical tokens");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "token0 address(0)");
    }

    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address _pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes32 initCodeHash = keccak256(type(Pair).creationCode);
        _pair = address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factory, salt, initCodeHash)))));
    }

    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint112 reserveA, uint112 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        address pair = pairFor(factory, tokenA, tokenB);
        (uint112 _reserve0, uint112 _reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = token0 == tokenA ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
    }

    function quote(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "invalid input");
        require(reserveIn > 0 && reserveOut > 0, "not enough");
        amountOut = amountIn * reserveOut / reserveIn;
    }

    function getAmountOut(uint256 amountIn, uint256 _reserveIn, uint256 _reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "invalid input");
        require(_reserveIn > 0 && _reserveOut > 0, "not enough");
        uint256 fenzi = _reserveOut * amountIn * 997;
        uint256 fenmu = _reserveIn * 1000 + amountIn * 997;
        amountOut = fenzi / fenmu;
    }

    function getAmountIn(uint256 amountOut, uint256 _reserveIn, uint256 _reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "invalid input");
        require(_reserveIn > 0 && _reserveOut > 0, "not enough");
        uint256 fenzi = _reserveIn * amountOut * 1000;
        uint256 fenmu = (_reserveOut - amountOut) * 997;
        amountIn = fenzi / fenmu + 1;
    }

    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "invalid path");
        uint256 pathLength = path.length;
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < pathLength - 1; i++) {
            (uint256 _reserveIn, uint256 _reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], _reserveIn, _reserveOut);
        }
    }

    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "invalid path");
        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 _reserveIn, uint256 _reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], _reserveIn, _reserveOut);
        }
    }
}
