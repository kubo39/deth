import std.json;
import std.array:replace;
import std.stdio;
import std.conv:to,text;
import std.bigint:BigInt;
import deth;

enum abiPath = "contractBuild/Test.abi";
enum binPath = "contractBuild/Test.bin";
 alias TestContract = Contract!(abiPath,"0x"~import(binPath));

void main()
{
    import std.process:environment;
    auto host = environment.get("RPC_HOST", "127.0.0.1"); 
    IEthRPC eth = new RPCConnector("http://"~host~":8545");
    auto c = new TestContract(eth);
    c.deploy(32);
    c.writeln;
    c.get(eth.eth_accounts[0].BigInt); 
}

unittest {
    IEthRPC c = new RPCConnector("http://127.0.0.1:8545");
    string[] accounts =  c.eth_accounts;
    string firstAccount = accounts[0];
    c.web3_clientVersion.writeln;
    c.web3_sha3("0x68656c6c6f20776f726c64").writeln;
    c.net_version.writeln;
    c.net_listening.writeln;
    c.net_peerCount.writeln;
    c.eth_protocolVersion.writeln;
    c.eth_getBalance(firstAccount, "latest".JSONValue).writeln;
    c.eth_syncing.writeln;
    writeln("Hashrate: ", c.eth_hashrate);
    Transaction tr = {from: firstAccount, to: accounts[0], value: 100};
    c.eth_sendTransaction(tr);
    c.eth_getBalance(firstAccount, "latest".JSONValue).writeln;
}

unittest{
    IEthRPC c = new RPCConnector("http://127.0.0.1:8545");
    string[] accounts =  c.eth_accounts;
    writeln("First account's balance: ", 
            c.eth_getBalance(accounts[0], "latest".JSONValue).BigInt);
    writeln("Second account's balance: ", 
            c.eth_getBalance(accounts[1], "latest".JSONValue).BigInt);
    Transaction tr = {from: accounts[0], to: accounts[1], value: 1000000};
    c.eth_sendTransaction(tr);
    writeln("First account's balance: ", 
            c.eth_getBalance(accounts[0], "latest".JSONValue)
            .BigInt);
    writeln("Second account's balance: ", 
            c.eth_getBalance(accounts[1], "latest".JSONValue).BigInt);
}
