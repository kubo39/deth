// ported from https://github.com/alloy-rs/examples/blob/main/examples/contracts/examples/deploy_from_contract.rs

import std.bigint;
import std.conv : to;
import std.stdio;

import deth;

enum abiPath = "artifacts/Counter.abi";
enum binPath = "artifacts/Counter.bin";

immutable CounterABI = ContractABI.load!abiPath("Counter");
alias CounterContract = Contract!CounterABI;

void main()
{
    auto conn = new RPCConnector("http://127.0.0.1:8545");

    const accounts = conn.remoteAccounts();

    auto bytecode = import(binPath).convTo!bytes;
    const chainid = conn.net_version.to!ulong;
    Transaction tx = {
        from: accounts[0],
        data: bytecode,
        chainid: chainid,
    };

    const txHash = conn.sendTransaction(tx);
    const receipt = conn.getTransactionReceipt(txHash);
    const contractAddress = receipt.get.contractAddress;
    assert(!contractAddress.isNull);
    writeln("Deployed contract at address: ", contractAddress.get.convTo!string.ox);

    auto contract = new CounterContract(conn, contractAddress.get);

    const txHash2 = contract.setNumber(42.BigInt).send();
    const receipt2 = conn.getTransactionReceipt(txHash2);
    writeln("Set number to 42: ", txHash2.convTo!string.ox);

    const txHash3 = contract.increment().send();
    conn.getTransactionReceipt(txHash3);
    writeln("Incremented number: ", txHash3.convTo!string.ox);

    const number = contract.number();
    writeln("Retrieved number: ", number);
}
