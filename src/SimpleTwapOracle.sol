// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUniswapV2Pair.sol";

contract SimpleTwapOracle {
    uint256 public constant Q112 = 2 ** 112;

    IUniswapV2Pair public immutable pair;
    address public immutable token0;
    address public immutable token1;
    uint256 public immutable period;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;
    uint256 public price0Average;
    uint256 public price1Average;

    constructor(address _pair, uint256 _period) {
        require(_pair != address(0), "zero address");
        require(_period > 0, "invalid period");

        pair = IUniswapV2Pair(_pair);
        token0 = IUniswapV2Pair(_pair).token0();
        token1 = IUniswapV2Pair(_pair).token1();
        period = _period;

        price0CumulativeLast = IUniswapV2Pair(_pair).price0CumulativeLast();
        price1CumulativeLast = IUniswapV2Pair(_pair).price1CumulativeLast();
        (,, blockTimestampLast) = IUniswapV2Pair(_pair).getReserves();
    }

    function update() external {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = currentCumulativePrices();
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }

        require(timeElapsed >= period, "period not elapsed");

        price0Average = (price0Cumulative - price0CumulativeLast) / timeElapsed;
        price1Average = (price1Cumulative - price1CumulativeLast) / timeElapsed;

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function consult(address tokenIn, uint256 amountIn) external view returns (uint256 amountOut) {
        require(amountIn > 0, "invalid amount");

        if (tokenIn == token0) {
            require(price0Average > 0, "missing average");
            amountOut = price0Average * amountIn / Q112;
        } else if (tokenIn == token1) {
            require(price1Average > 0, "missing average");
            amountOut = price1Average * amountIn / Q112;
        } else {
            revert("invalid token");
        }
    }

    function currentCumulativePrices()
        public
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp = uint32(block.timestamp % 2 ** 32);
        price0Cumulative = pair.price0CumulativeLast();
        price1Cumulative = pair.price1CumulativeLast();

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLastPair) = pair.getReserves();
        if (blockTimestampLastPair != blockTimestamp && reserve0 != 0 && reserve1 != 0) {
            uint32 timeElapsed;
            unchecked {
                timeElapsed = blockTimestamp - blockTimestampLastPair;
            }
            price0Cumulative += (uint256(reserve1) << 112) / reserve0 * timeElapsed;
            price1Cumulative += (uint256(reserve0) << 112) / reserve1 * timeElapsed;
        }
    }
}
