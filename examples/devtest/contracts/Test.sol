// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
contract Test{
    mapping(address => int32) map;
    uint[][] _b;
    constructor(int32 d){
        map[msg.sender] = d;
        _b.push([1, 2, 3]);
        _b.push([4, 5]);
    }
    function set(int32 value)public{
        map[msg.sender] = value;
    }
    
    function get(address user) public view returns(int32){ 
        return map[user];
    }
    
    function test(uint a, uint[][] memory b, string memory c) public view{
        require(a == 10, "test A not passed");
        require(testB(b) , "test B not passed: array decoding");
        require(testC(c) , "test C not passed: string decoding");
    }

    function testB(uint[][] memory b) internal view returns(bool){
        if(b.length != _b.length) return false;
        for (uint i = 0; i < b.length; i++){
            if(b[i].length != _b[i].length) return false;
            for(uint j = 0; j < b[i].length; j++){
                if(b[i][j] != _b[i][j]) return false;
            }
        }
        return true;
    }

    function testC(string memory c)internal pure returns(bool){
        return keccak256(abi.encode(c)) == keccak256(abi.encode("Hello, World!"));
    }
}
