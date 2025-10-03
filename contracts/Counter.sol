// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Counter {
    address public owner;
    uint256 public count;

    event CountChanged(uint256 oldValue, uint256 newValue, address indexed changedBy);

    constructor(uint256 _initial) {
        owner = msg.sender;
        count = _initial;
    }

    function increment() external {
        uint256 old = count;
        count += 1;
        emit CountChanged(old, count, msg.sender);
    }

    function decrement() external {
        require(count > 0, "Counter: underflow");
        uint256 old = count;
        count -= 1;
        emit CountChanged(old, count, msg.sender);
    }

    function setCount(uint256 _val) external {
        require(msg.sender == owner, "Not owner");
        uint256 old = count;
        count = _val;
        emit CountChanged(old, count, msg.sender);
    }
}
