import std.bigint : BigInt;
import std.process : environment;
import std.logger;
import std.stdio;

import deth;

enum abiPath = "contractBuild/Test.abi";
enum binPath = "contractBuild/Test.bin";

static immutable TestABI = ContractABI.load!abiPath("Test");
alias TestContract = Contract!TestABI;

void main()
{
    globalLogLevel = LogLevel.all;
    TestContract.bytecode = import(binPath).convTo!bytes;

    auto host = environment.get("RPC_HOST", "127.0.0.1");
    auto conn = new RPCConnector("http://" ~ host ~ ":8545");
    auto test = TestContract.deploy(conn, 32.wei);

    auto vc = new NonABIContract(conn, test.address);
    auto accounts = conn.remoteAccounts;
    vc.callMethodS!("get(address)", BigInt)(accounts[0]).writeln;
    test.get(accounts[0]).writeln;
    test.set(33.BigInt).send(accounts[0].From);
    test.get(accounts[0]).writeln;
    vc.sendMethodS!"set(int32)"(34).send(accounts[0].From);
    test.get(accounts[0]).writeln;
    test.getSender(accounts[3]).convTo!string.writeln;
}
