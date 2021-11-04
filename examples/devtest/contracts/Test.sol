// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
contract Test{
    mapping(address => int32) map;
    uint[] _b = [1,2,3,4,5];

    constructor(int32 d){
        map[msg.sender] = d;
    }
    function set(int32 value)public{
        map[msg.sender] = value;
    }
    
    function get(address user) public view returns(int32){ 
        return map[user];
    }
    
    function test(uint a, uint[] memory b) public view{
        
        require(a == 10 &&
                testB(b), 
                "Test no passed Test no passed Test no passed Test no passed ");
    }

    function testB(uint[]memory b) internal view returns(bool){
        if(b.length != _b.length) return false;
        for(uint i = 0;i < b.length; i++ ){
            if(b[i]!= _b[i]) return false;
        }
        return true;
    }
    
}
