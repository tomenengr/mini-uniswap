//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Pair.sol";

contract GetHashTest is Test {
    function testPrintInitCodeHash() public pure {
        // type(ContractName).creationCode 可以直接获取该合约的创建字节码
        bytes32 initCodeHash = keccak256(type(Pair).creationCode);

        console.log("----- INIT CODE HASH -----");
        console.logBytes32(initCodeHash);
        console.log("-------------------------------");
    }
}
