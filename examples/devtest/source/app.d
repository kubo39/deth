import std.json;
import std.array : replace;
import std.stdio;
import std.conv : to, text;
import std.bigint : BigInt;
import structjson : parseJSON;
import deth;

enum abiPath = "contractBuild/Test.abi";
enum binPath = "contractBuild/Test.bin";
static immutable TestABI = import(abiPath).parseJSON.ContractABI;
alias TestContract = Contract!TestABI;

void main()
{
    TestContract.deployedBytecode = import(binPath);
    import std.process : environment;

    auto host = environment.get("RPC_HOST", "127.0.0.1");
    auto eth = new RPCConnector("http://" ~ host ~ ":8545");
    auto test = TestContract.deploy(eth, 32);
    test.get(eth.eth_accounts[0].convTo!Address).writeln;
}
