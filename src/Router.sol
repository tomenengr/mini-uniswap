// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./Pair.sol";
import "./Library.sol";
import "./TransferHelper.sol";
import "./interfaces/IWETH.sol";

contract Router {
    address public immutable factory;
    address public immutable WETH;

    constructor(address _factory, address _WETH) {
        require(_factory != address(0) && _WETH != address(0), "zero address");
        factory = _factory;
        WETH = _WETH;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "expired");
        _;
    }

    receive() external payable {
        // Only accept ETH from WETH withdraw.
        require(msg.sender == WETH, "only WETH");
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        // 1. 如果池子根本不存在，立刻帮用户创建
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }

        // 2. 获取当前的真实库存（加池子没有方向，统一叫 reserveA 和 reserveB）
        (uint256 reserveA, uint256 reserveB) = Library.getReserves(factory, tokenA, tokenB);

        // 3. 核心计算逻辑
        if (reserveA == 0 && reserveB == 0) {
            // 情况 A：新池子（或者池子被清空了），没人定过价，用户想加多少就按多少来
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 情况 B：老池子，必须严格遵守 K 值比例
            // 尝试按用户的 A 预期，算出需要的 B
            uint256 amountBOptimal = Library.quote(amountADesired, reserveA, reserveB);

            if (amountBOptimal <= amountBDesired) {
                // 如果需要的 B 没超标，那就检查底线：算出来的 B 必须大于用户的滑点容忍下限
                require(amountBOptimal >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // 如果需要的 B 超标了，说明按照 A 拉满不现实。
                // 我们换个思路，按用户的 B 预期，反向算出需要的 A。
                // 注意 quote 的传参顺序变了：(输入量B, 池子储备B, 池子储备A)
                uint256 amountAOptimal = Library.quote(amountBDesired, reserveB, reserveA);

                // 同样，检查算出来的 A 是不是在预期范围内，并且高于底线
                require(amountAOptimal <= amountADesired, "UniswapV2Router: EXCESSIVE_A_AMOUNT"); // 其实这一步数学上一定成立，但为了严谨可留可不留
                require(amountAOptimal >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");

                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // 注意：这个函数带上了你之前写的 ensure(deadline) 修饰器，防止交易超时
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Step 1: 算账。调用你刚写好的内部函数，拿到真实的扣款金额
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);

        // Step 2: 寻址。使用 Library.pairFor 计算出池子的地址
        address pair = Library.pairFor(factory, tokenA, tokenB);

        // Step 3: 收钱。使用 TransferHelper 将用户的钱转入 Pair 合约
        // 语法提示：TransferHelper.safeTransferFrom(代币地址, 谁出钱, 钱打给谁, 金额);
        // 把 tokenA 转移进 pair
        // 把 tokenB 转移进 pair
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);

        // Step 4: 发货。调用 Pair 合约的 mint 函数，给 to 地址发放 LP Token
        // 语法提示：IUniswapV2Pair(pair).mint(to);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        // Step 1: 算账。调用你之前写好的 _addLiquidity 函数，拿到真实的扣款金额
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value, // 用户发过来的 ETH 就是他们的预期
            amountTokenMin,
            amountETHMin
        );

        // Step 2: 寻址。使用 Library.pairFor 计算出池子的地址
        address pair = Library.pairFor(factory, token, WETH);

        // Step 3: 收钱。把用户的 ERC20 代币转入 Pair 合约，把用户的 ETH 包成 WETH 转入 Pair 合约
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        // 把多余的 ETH 找零退回给用户（如果用户发过来的 ETH 超过了实际需要的）
        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }

        // 给 Pair 合约发送 ETH，Pair 合约会自动把它包成 WETH
        IWETH(WETH).deposit{value: amountETH}();
        require(IWETH(WETH).transfer(pair, amountETH), "WETH_TRANSFER_FAILED");

        // Step 4: 发货。调用 Pair 合约的 mint 函数，给 to 地址发放 LP Token
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        // Step 1: 寻址
        address pair = Library.pairFor(factory, tokenA, tokenB);

        // Step 2: 收凭证。把用户的 LP Token 转入 Pair 合约本身，准备销毁
        require(IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity), "TRANSFER_FROM_FAILED");

        // Step 3: 触发销毁。拿到绝对物理顺序的 0 和 1
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);

        // Step 4: 翻译与验收
        (address token0,) = Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);

        require(amountA >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        // Step 1: 寻址。使用 Library.pairFor 计算出池子的地址
        address pair = Library.pairFor(factory, token, WETH);

        // Step 2: 收货。把用户的 LP Token 转入 Pair 合约
        TransferHelper.safeTransferFrom(pair, msg.sender, pair, liquidity);

        // Step 3: 算账。调用 Pair 合约的 burn 函数，拿到用户应该收到的两种代币数量（其中一种是 WETH）
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(address(this));

        // Step 4: 验收。检查用户收到的金额是否都在他们的预期范围内
        (address token0,) = Library.sortTokens(token, WETH);
        (amountToken, amountETH) = token == token0 ? (amount0, amount1) : (amount1, amount0);

        require(amountToken >= amountTokenMin, "UniswapV2Router: INSUFFICIENT_TOKEN_AMOUNT");
        require(amountETH >= amountETHMin, "UniswapV2Router: INSUFFICIENT_ETH_AMOUNT");

        // Step 5: 发货。把用户的 ERC20 代币转回给用户，把 WETH 解包成 ETH 转回给用户
        TransferHelper.safeTransfer(token, to, amountToken);

        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(Library.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(path[0], msg.sender, Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
}
