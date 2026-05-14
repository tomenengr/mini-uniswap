//SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

contract ERC20 {
    uint256 public totalSupply;
    string public name;
    string public symbol;
    address public immutable owner;
    uint256 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
        totalSupply = 100000 * 10 ** 18;
        balanceOf[msg.sender] = totalSupply;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) public returns (bool) {
        require(balanceOf[msg.sender] >= value, "not enough");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(balanceOf[from] >= value, "not enough");
        require(allowance[from][msg.sender] >= value, "not approved");
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    function _mint(address account, uint256 value) internal {
        balanceOf[account] += value;
        totalSupply += value;
        emit Transfer(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        require(balanceOf[account] >= value, "not enough");
        balanceOf[account] -= value;
        totalSupply -= value;
        emit Transfer(account, address(0), value);
    }
}
