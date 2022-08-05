module deth.rpcconnector;

import std.digest : toHexString;
import std : Nullable;
import std.json : JSONValue;
import std.bigint;
import std.conv : to;
import std.range : chunks;
import std.algorithm : map, canFind;
import std.array : array, join;
import std.stdio;
import rpc.protocol.json;
import std.array : replace;
import deth.util.rlp : rlpEncode, cutBytes;
import deth.wallet : Wallet;

import deth.util;
import secp256k1 : secp256k1;
import core.thread : Thread, dur, Fiber;
import std.exception : enforce;
import std.experimental.logger;

enum BlockNumber
{
    EARLIEST = `earliest`,
    LATEST = `latest`,
    PENDING = `pending`
}

private interface IEthRPC
{
    string web3_clientVersion() @safe;
    string web3_sha3(string data) @safe;
    string net_version() @safe;
    bool net_listening() @safe;
    int net_peerCount() @safe;
    string eth_protocolVersion() @safe;
    JSONValue eth_syncing() @safe;
    string eth_coinbase() @safe;
    bool eth_mining() @safe;
    string eth_hashrate() @safe;
    string eth_gasPrice() @safe;
    string[] eth_accounts() @safe;
    string eth_blockNumber() @safe;
    string eth_getBalance(string address, JSONValue blockNumber) @safe;
    string eth_getStorageAt(string address, string pos, JSONValue blockNumber) @safe;
    string eth_getTransactionCount(string address, JSONValue blockNumber) @safe;
    string eth_getBlockTransactionCountByNumber(JSONValue blockNumber) @safe;
    string eth_getUncleCountByBlockNumber(JSONValue blockNumber) @safe;
    string eth_getCode(string address, JSONValue blockNumber) @safe;
    string eth_sign(string address, string data) @safe;
    string eth_signTransction(JSONValue tx) @safe;
    string eth_sendTransaction(JSONValue tx) @safe;
    string eth_sendRawTransaction(string data) @safe;
    string eth_call(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_estimateGas(JSONValue tx, JSONValue blockNumber) @safe;
    JSONValue eth_getBlockByHash(string blockHash, bool isFull) @safe;
    JSONValue eth_getBlockByNumber(JSONValue blockNumber, bool isFull) @safe;
    JSONValue eth_getTransactionByHash(string hash) @safe;
    JSONValue eth_getTransactionByBlockNumberAndIndex(JSONValue blockNumber, string index) @safe;
    JSONValue eth_getTransactionReceipt(string data) @safe;
}

private mixin template BlockNumberToJSON(alias block)
{
    static if (is(BlockParameter == BlockNumber))
        JSONValue _block = block;
    else static if (is(BigInt == BlockParameter))
        JSONValue _block = block.convTo!string.ox;
    else
        static assert(0, "BlockParameter not support type " ~ stringof(BlockParameter));
}

/// Connector to Ethereum rpc endpoint
class RPCConnector : HttpJsonRpcAutoClient!IEthRPC
{
    /// Private keys stored by connector
    Wallet wallet;

    /// coeficient used for estimated gas
    uint gasEstimatePercentage = 100;

    this(string url) @safe
    {
        super(url);
    }

    BigInt getBalance(BlockParameter)(ubyte[20] address, BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return eth_getBalance(address.convTo!string.ox, _block).BigInt;
    }

    BigInt estimateGas(BlockParameter)(Transaction tx, BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return super.eth_estimateGas(tx.toJSON, _block).BigInt;
    }

    BigInt gasPrice() @safe
    {
        return super.eth_gasPrice.BigInt;
    }

    ubyte[] call(BlockParameter)(Transaction tx, BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return super.eth_call(tx.toJSON, _block)[2 .. $].convTo!bytes;
    }

    ulong getTransactionCount(BlockParameter)(Address address,
        BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return eth_getTransactionCount(address.toHexString.ox, _block)[2 .. $].to!ulong(16);
    }

    Nullable!TransactionReceipt getTransactionReceipt(Hash h) @safe
    {
        JSONValue a = eth_getTransactionReceipt(h.convTo!string.ox);
        if (a.isNull)
        {
            Nullable!TransactionReceipt tx;
            return tx;
        }

        return Nullable!TransactionReceipt(a.convTo!TransactionReceipt);
    }

    auto getTransaction(Hash txHash) @safe
    {
        return eth_getTransactionByHash(txHash.convTo!string.ox).convTo!TransactionInfo;
    }

    Hash sendRawTransaction(const Transaction tx) @safe
    {
        auto rawTx = wallet.signTransaction(tx);
        auto hash = eth_sendRawTransaction(rawTx.convTo!string.ox).convTo!Hash;
        tracef("sent tx %s", hash.convTo!string.ox);
        return hash;
    }

    Hash sendTransaction(const Transaction tx) @safe
    {

        JSONValue jtx = ["from": tx.from.get.convTo!string.ox,];
        if (!tx.value.isNull)
            jtx["value"] = tx.value.get.convTo!string.ox;
        if (!tx.gasPrice.isNull)
            jtx["gasPrice"] = tx.gasPrice.get.convTo!string.ox;
        if (!tx.gas.isNull)
            jtx["gas"] = tx.gas.get.convTo!string.ox;
        if (!tx.data.isNull)
            jtx["data"] = tx.data.get.convTo!string.ox;
        if (!tx.to.isNull)
            jtx["to"] = tx.to.get.convTo!string.ox;
        logf("Json string: %s", jtx.toString);
        auto hash = eth_sendTransaction(jtx).convTo!Hash;
        tracef("sent tx %s", hash.convTo!string.ox);
        return hash;
    }

    Address[] accounts() const @safe
    {
        return wallet.addresses;
    }

    Address[] remoteAccounts() @safe
    {
        return eth_accounts.map!(a => a.convTo!Address).array;
    }

    bool isUnlocked(Address addr) const @safe
    {
        return accounts.canFind(addr);
    }

    bool isUnlockedRemote(Address addr) @safe
    {
        return remoteAccounts.canFind(addr);
    }

    TransactionReceipt waitForTransactionReceipt(Hash txHash) @safe
    {
        ulong count;
        while (getTransaction(txHash).blockHash.isNull)
        {
            enforce(count < 500, "Timeout for waiting tx"); // TODO: add timeout into connector
            () @trusted { Thread.sleep(200.dur!"msecs"); }();
            count++;
        }
        return getTransactionReceipt(txHash).get;
    }
}

@("sending legacy tx")
unittest
{
    auto conn = new RPCConnector("https://rpc.qtestnet.org/");
    conn.wallet.addPrivateKey("beb75b08049e9316d1375999c7d968f3c23fdf606b296fcdfc9a41cdd7e7347c");
    import deth.util.decimals;

    Transaction tx = {
        to: "0xdddddddd0d0d0d0d0d0d0ddddddddd".convTo!Address,
        value: 16.wei,
        data: cast(bytes) "\xdd\xdd\xdd\xdd Dlang - Fast code, fast.",};
        auto txHash = SendableTransaction(tx, conn).send();
        conn.getTransaction(txHash);
        conn.waitForTransactionReceipt(txHash);
        assert(!conn.getTransactionReceipt(txHash).isNull);
    }

    @("sending eip-155 tx")
    unittest
    {
        auto conn = new RPCConnector("https://rpc.qtestnet.org/");
        conn.wallet.addPrivateKey(
            "beb75b08049e9316d1375999c7d968f3c23fdf606b296fcdfc9a41cdd7e7347d");
        import deth.util.decimals;

        Transaction tx = {
            to: "0xdddddddd0d0d0d0d0d0d0ddddddddd".convTo!Address,
            value: 16.wei,
            data: cast(bytes) "\xdd\xdd\xdd\xdd Dlang - Fast code, fast.",
            chainid: conn.net_version.to!ulong,
    };
    auto txHash = SendableTransaction(tx, conn).send();
    conn.getTransaction(txHash);
    conn.waitForTransactionReceipt(txHash);
    assert(!conn.getTransactionReceipt(txHash).isNull);
}
