import std.json;
import std.array : replace;
import std.stdio;
import std.conv : to, text;
import std.bigint : BigInt;
import deth;

enum abiPath = "contractBuild/Test.abi";
enum binPath = "contractBuild/Test.bin";
alias TestContract = Contract!(abiPath, "0x" ~ import(binPath));

void main()
{
    import std.process : environment;

    auto host = environment.get("RPC_HOST", "127.0.0.1");
    auto eth = new RPCConnector("http://" ~ host ~ ":8545");
    auto c = new TestContract(eth);
    c.deploy(32);
    c.writeln;
    c.get(eth.eth_accounts[0].BigInt);
    c.callMethod!"test(uint256,uint256[][],string)"(10, [[1, 2, 3], [4, 5]], "Hello, World!");
}
