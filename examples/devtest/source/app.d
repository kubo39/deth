import std.process : environment;
import std.logger;
import std.stdio;

import deth;

enum abiPath = "contractBuild/Test.abi";
enum binPath = "contractBuild/Test.bin";

struct TestContract
{
    mixin DefineContract!(loadABI!abiPath, "Test");
}

void main()
{
    globalLogLevel = LogLevel.all;
    TestContract.setBytecode(import(binPath).convTo!bytes);

    auto host = environment.get("RPC_HOST", "127.0.0.1");
    auto conn = new RPCConnector("http://" ~ host ~ ":8545");
    auto test = TestContract.deploy(conn, 32);

    auto vc = new GenericContract!RPCConnector(conn, test.address);
    auto accounts = conn.remoteAccounts;

    // Call using GenericContract (dynamic)
    vc.call!("get(address)", int)(accounts[0]).writeln;

    // Call using typed contract
    test.get(accounts[0]).call().writeln;

    // Send transaction
    test.set(33).from(accounts[0]).send();
    test.get(accounts[0]).call().writeln;

    // Send using GenericContract
    vc.send!"set(int32)"(34);
    test.get(accounts[0]).call().writeln;

    test.getSender().from(accounts[3]).call().convTo!string.writeln;
}
