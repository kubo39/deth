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
    TestContract.deployedBytecode = import(binPath).convTo!bytes;
    import std.process : environment;

    auto host = environment.get("RPC_HOST", "127.0.0.1");
    auto conn = new RPCConnector("http://" ~ host ~ ":8545");
    auto test = TestContract.deploy(conn, 32);

    auto accounts = conn.remoteAccounts;
    test.get(accounts[0]).writeln;
    test.set(33.BigInt).from(accounts[0]).send;
    test.get(accounts[0]).writeln;
    test.getSender(accounts[3]).convTo!string.writeln;
}
