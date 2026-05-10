//SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

/**
 * @title Math
 * @dev 算术运算库。改为了 library 形式以节省部署 Gas 并在调用时内联。
 */
library Math {
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    /**
     * @dev 计算 y 的平方根。使用的是巴比伦法（Babylonian method）。
     * 优化点：
     * 1. 改为 library 形式。
     * 2. 使用 unchecked 减少溢出检查的 Gas 开销。
     * 3. 修正了初始值 x 的计算逻辑。
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) return 0;

        z = y;
        uint256 x = (y + 1) / 2;
        while (x < z) {
            z = x;
            unchecked {
                x = (y / x + x) / 2;
            }
        }
    }
}
