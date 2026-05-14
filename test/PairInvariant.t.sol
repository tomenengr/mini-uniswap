// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/StdInvariant.sol";
import "forge-std/Test.sol";

import "../src/ERC20.sol";
import "../src/Factory.sol";
import "../src/Library.sol";
import "../src/Pair.sol";

contract PairActionHandler {
    Pair public pair;
    ERC20 public token0;
    ERC20 public token1;

    constructor(Pair _pair, ERC20 _token0, ERC20 _token1) {
        pair = _pair;
        token0 = _token0;
        token1 = _token1;
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        amount0 = _bound(amount0, 1e12, _maxSpend(token0));
        amount1 = _bound(amount1, 1e12, _maxSpend(token1));

        token0.transfer(address(pair), amount0);
        token1.transfer(address(pair), amount1);
        pair.mint(address(this));
    }

    function swap0For1(uint256 amount0In) external {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        amount0In = _bound(amount0In, 1e9, _maxSpend(token0));
        uint256 amount1Out = Library.getAmountOut(amount0In, reserve0, reserve1);
        if (amount1Out == 0 || amount1Out >= reserve1) return;

        token0.transfer(address(pair), amount0In);
        pair.swap(0, amount1Out, address(this), "");
    }

    function swap1For0(uint256 amount1In) external {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        amount1In = _bound(amount1In, 1e9, _maxSpend(token1));
        uint256 amount0Out = Library.getAmountOut(amount1In, reserve1, reserve0);
        if (amount0Out == 0 || amount0Out >= reserve0) return;

        token1.transfer(address(pair), amount1In);
        pair.swap(amount0Out, 0, address(this), "");
    }

    function skim(uint256 amount0, uint256 amount1) external {
        amount0 = _bound(amount0, 0, _maxSpend(token0));
        amount1 = _bound(amount1, 0, _maxSpend(token1));

        if (amount0 > 0) token0.transfer(address(pair), amount0);
        if (amount1 > 0) token1.transfer(address(pair), amount1);
        pair.skim(address(this));
    }

    function sync(uint256 amount0, uint256 amount1) external {
        amount0 = _bound(amount0, 0, _maxSpend(token0));
        amount1 = _bound(amount1, 0, _maxSpend(token1));

        if (amount0 > 0) token0.transfer(address(pair), amount0);
        if (amount1 > 0) token1.transfer(address(pair), amount1);
        pair.sync();
    }

    function _maxSpend(ERC20 token) internal view returns (uint256) {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return 0;
        return balance < 5 ether ? balance : 5 ether;
    }

    function _bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return max;
        return min + (value % (max - min + 1));
    }
}

contract SwapOnlyHandler {
    Pair public pair;
    ERC20 public token0;
    ERC20 public token1;
    uint256 public initialK;
    uint256 public lastK;
    bool public kNeverDecreased = true;

    constructor(Pair _pair, ERC20 _token0, ERC20 _token1) {
        pair = _pair;
        token0 = _token0;
        token1 = _token1;
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        initialK = uint256(reserve0) * reserve1;
        lastK = initialK;
    }

    function swap0For1(uint256 amount0In) external {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        amount0In = _bound(amount0In, 1e9, _maxSpend(token0));
        uint256 amount1Out = Library.getAmountOut(amount0In, reserve0, reserve1);
        if (amount1Out == 0 || amount1Out >= reserve1) return;

        token0.transfer(address(pair), amount0In);
        pair.swap(0, amount1Out, address(this), "");
        _recordK();
    }

    function swap1For0(uint256 amount1In) external {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        amount1In = _bound(amount1In, 1e9, _maxSpend(token1));
        uint256 amount0Out = Library.getAmountOut(amount1In, reserve1, reserve0);
        if (amount0Out == 0 || amount0Out >= reserve0) return;

        token1.transfer(address(pair), amount1In);
        pair.swap(amount0Out, 0, address(this), "");
        _recordK();
    }

    function _recordK() internal {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 currentK = uint256(reserve0) * reserve1;
        if (currentK < lastK) kNeverDecreased = false;
        lastK = currentK;
    }

    function _maxSpend(ERC20 token) internal view returns (uint256) {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return 0;
        return balance < 5 ether ? balance : 5 ether;
    }

    function _bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return max;
        return min + (value % (max - min + 1));
    }
}

contract PairReserveInvariantTest is StdInvariant, Test {
    Pair pair;
    ERC20 token0;
    ERC20 token1;
    PairActionHandler handler;

    function setUp() public {
        (pair, token0, token1) = _deployPairWithLiquidity();
        handler = new PairActionHandler(pair, token0, token1);
        token0.transfer(address(handler), 1000 ether);
        token1.transfer(address(handler), 1000 ether);
        targetContract(address(handler));
    }

    function invariant_reservesMatchBalances() public {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(token0.balanceOf(address(pair)), reserve0);
        assertEq(token1.balanceOf(address(pair)), reserve1);
    }

    function _deployPairWithLiquidity() internal returns (Pair pair_, ERC20 token0_, ERC20 token1_) {
        Factory factory = new Factory(address(this));
        ERC20 tokenA = new ERC20("Token A", "A");
        ERC20 tokenB = new ERC20("Token B", "B");
        pair_ = Pair(factory.createPair(address(tokenA), address(tokenB)));

        (token0_, token1_) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
        token0_.transfer(address(pair_), 100 ether);
        token1_.transfer(address(pair_), 100 ether);
        pair_.mint(address(this));
    }
}

contract PairSwapKInvariantTest is StdInvariant, Test {
    Pair pair;
    ERC20 token0;
    ERC20 token1;
    SwapOnlyHandler handler;

    function setUp() public {
        (pair, token0, token1) = _deployPairWithLiquidity();
        handler = new SwapOnlyHandler(pair, token0, token1);
        token0.transfer(address(handler), 1000 ether);
        token1.transfer(address(handler), 1000 ether);
        targetContract(address(handler));
    }

    function invariant_kDoesNotDecreaseAfterSwaps() public {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 currentK = uint256(reserve0) * reserve1;
        assertGe(currentK, handler.initialK());
        assertTrue(handler.kNeverDecreased());
    }

    function _deployPairWithLiquidity() internal returns (Pair pair_, ERC20 token0_, ERC20 token1_) {
        Factory factory = new Factory(address(this));
        ERC20 tokenA = new ERC20("Token A", "A");
        ERC20 tokenB = new ERC20("Token B", "B");
        pair_ = Pair(factory.createPair(address(tokenA), address(tokenB)));

        (token0_, token1_) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
        token0_.transfer(address(pair_), 100 ether);
        token1_.transfer(address(pair_), 100 ether);
        pair_.mint(address(this));
    }
}
