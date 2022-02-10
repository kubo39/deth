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
    import std.process : environment;

    TestABI.writeln;
    TestContract.stringof.writeln;
    auto host = environment.get("RPC_HOST", "127.0.0.1");
    auto eth = new RPCConnector("http://" ~ host ~ ":8545");
}
