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
    c.web3_sha3("0x68656c6c6f20776f726c64").writeln;
    c.net_version.writeln;
    c.net_listening.writeln;
    c.net_peerCount.writeln;
    c.eth_protocolVersion.writeln;
    c.eth_getBalance("0x9de6f9355542ca6D16a70A57bE8Ecb751BfFc72c", "latest").writeln;
}
