import std.json;
import std.array:replace;
import std.stdio;
import contract;

alias ERC20 = Contract!ERC20abi;

void main()
{   
    ERC20 contract;
    contract.transfer("0x188281811", "123456");
    contract.approve("0x,123", "14134");
    contract.transferFrom("0x123123", "0x434534", "123213");
}
