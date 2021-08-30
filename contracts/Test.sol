// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
contract Test{
    mapping(address => int32) map;

    function set(int32 value)public{
        map[msg.sender] = value;
    }
    
    function get(address user) public view returns(int32){ 
        return map[user];
    }
    
    
}
