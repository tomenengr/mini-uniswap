// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TransferHelper.sol";

contract DemoTokenFaucet {
    address public immutable tokenA;
    address public immutable tokenB;
    address public owner;
    uint256 public amountA;
    uint256 public amountB;
    bool public paused;

    mapping(address => bool) public claimed;

    event Claimed(address indexed account, uint256 amountA, uint256 amountB);
    event ClaimAmountsSet(uint256 amountA, uint256 amountB);
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    event PausedSet(bool paused);
    event Refilled(address indexed from, uint256 amountA, uint256 amountB);
    event Withdrawn(address indexed to, uint256 amountA, uint256 amountB);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _tokenA, address _tokenB, uint256 _amountA, uint256 _amountB) {
        require(_tokenA != address(0) && _tokenB != address(0), "zero token");
        require(_tokenA != _tokenB, "same token");
        require(_amountA > 0 || _amountB > 0, "zero amount");

        tokenA = _tokenA;
        tokenB = _tokenB;
        owner = msg.sender;
        amountA = _amountA;
        amountB = _amountB;

        emit OwnerSet(address(0), msg.sender);
        emit ClaimAmountsSet(_amountA, _amountB);
    }

    function claim() external {
        require(!paused, "paused");
        require(!claimed[msg.sender], "already claimed");

        claimed[msg.sender] = true;
        if (amountA > 0) TransferHelper.safeTransfer(tokenA, msg.sender, amountA);
        if (amountB > 0) TransferHelper.safeTransfer(tokenB, msg.sender, amountB);

        emit Claimed(msg.sender, amountA, amountB);
    }

    function setClaimAmounts(uint256 _amountA, uint256 _amountB) external onlyOwner {
        require(_amountA > 0 || _amountB > 0, "zero amount");
        amountA = _amountA;
        amountB = _amountB;
        emit ClaimAmountsSet(_amountA, _amountB);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedSet(_paused);
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnerSet(owner, newOwner);
        owner = newOwner;
    }

    function refill(uint256 amountAIn, uint256 amountBIn) external {
        require(amountAIn > 0 || amountBIn > 0, "zero refill");
        if (amountAIn > 0) TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), amountAIn);
        if (amountBIn > 0) TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), amountBIn);
        emit Refilled(msg.sender, amountAIn, amountBIn);
    }

    function withdraw(address to, uint256 amountAOut, uint256 amountBOut) external onlyOwner {
        require(to != address(0), "zero to");
        require(amountAOut > 0 || amountBOut > 0, "zero withdraw");
        if (amountAOut > 0) TransferHelper.safeTransfer(tokenA, to, amountAOut);
        if (amountBOut > 0) TransferHelper.safeTransfer(tokenB, to, amountBOut);
        emit Withdrawn(to, amountAOut, amountBOut);
    }
}
