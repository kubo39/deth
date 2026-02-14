// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

contract Counter {
    uint256 public number;

    event NumberChanged(address indexed by, uint256 newNumber);

    function setNumber(uint256 newNumber) public {
        number = newNumber;
        emit NumberChanged(msg.sender, newNumber);
    }

    function increment() public {
        number++;
        emit NumberChanged(msg.sender, number);
    }
}
