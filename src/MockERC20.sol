// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockERC20 {
    //////////////////////////// STATE VARIABLES ///////////////////////////////

    mapping(address user => uint256 balance) public balanceOf;
    mapping(address user => mapping(address delegatedUser => uint256 amount)) public allowance;

    //////////////////////////// EXTERNAL FUNCTIONS /////////////////////////////

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address delegatedUser, uint256 amount) external returns (bool) {
        allowance[msg.sender][delegatedUser] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
