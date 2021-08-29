import std.json;
import std.array:replace;
import std.stdio;
import contract;
import rpcconnector:RPCConnector;
alias ERC20 = Contract!ERC20abi;

void main()
{
    auto c = new RPCConnector("http://127.0.0.1:8545");
    c.web3_clientVersion.writeln;
}
