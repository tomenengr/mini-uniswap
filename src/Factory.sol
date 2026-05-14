//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pair.sol";

contract Factory {
    address public feeTo;
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _feeToSetter) {
        require(_feeToSetter != address(0), "zero address");
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) public returns (address pair) {
        require(tokenA != tokenB, "same coin");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "address(0)");
        require(getPair[token0][token1] == address(0), "duplicate");

        // Must match Library.pairFor salt derivation to keep the pair address deterministic.
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        bytes memory bytecode = type(Pair).creationCode;

        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        Pair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) public {
        require(msg.sender == feeToSetter, "forbidden");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) public {
        require(msg.sender == feeToSetter, "forbidden");
        require(_feeToSetter != address(0), "zero address");
        feeToSetter = _feeToSetter;
    }
}
