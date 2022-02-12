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
import deth.util.types;
import secp256k1 : secp256k1;
import core.thread : Thread, dur, Fiber;

enum BlockNumber
{
    EARLIEST = `earliest`,
    LATEST = `latest`,
    PENDING = `pending`
}

private interface IEthRPC
{
    string web3_clientVersion();
    string web3_sha3(string data);
    string net_version();
    bool net_listening();
    int net_peerCount();
    string eth_protocolVersion();
    JSONValue eth_syncing();
    string eth_coinbase();
    bool eth_mining();
    string eth_hashrate();
    string eth_gasPrice();
    string[] eth_accounts();
    string eth_blockNumber();
    string eth_getBalance(string address, JSONValue blockNumber);
    string eth_getStorageAt(string address, string pos, JSONValue blockNumber);
    string eth_getTransactionCount(string address, JSONValue blockNumber);
    string eth_getBlockTransactionCountByNumber(JSONValue blockNumber);
    string eth_getUncleCountByBlockNumber(JSONValue blockNumber);
    string eth_getCode(string address, JSONValue blockNumber);
    string eth_sign(string address, string data);
    string eth_signTransction(JSONValue tx);
    string eth_sendTransaction(JSONValue tx);
    string eth_sendRawTransaction(string data);
    string eth_call(JSONValue tx, JSONValue blockNumber);
    JSONValue eth_getBlockByHash(string blockHash, bool isFull);
    JSONValue eth_getBlockByNumber(JSONValue blockNumber, bool isFull);
    JSONValue eth_getTransactionByHash(string hash);
    JSONValue eth_getTransactionByBlockNumberAndIndex(JSONValue blockNumber, string index);
    JSONValue eth_getTransactionReceipt(string data);
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
    secp256k1[Address] wallet;

    this(string url)
    {
        super(url);
    }

    BigInt getBalance(BlockParameter)(ubyte[20] address, BlockParameter block = BlockNumber.LATEST)
    {
        mixin BlockNumberToJSON!block;
        return eth_getBalance(address.convTo!string.ox, _block).BigInt;
    }

    ubyte[] call(BlockParameter)(Transaction tx, BlockParameter block = BlockNumber.LATEST)
    {
        mixin BlockNumberToJSON!block;
        return super.eth_call(tx.toJSON, _block)[2 .. $].convTo!bytes;
    }

    ulong getTransactionCount(BlockParameter)(Address address,
            BlockParameter block = BlockNumber.LATEST)
    {
        mixin BlockNumberToJSON!block;
        return eth_getTransactionCount(address.toHexString.ox, _block)[2 .. $].to!ulong(16);
    }

    Nullable!TransactionReceipt getTransactionReceipt(Hash h)
    {
        JSONValue a = eth_getTransactionReceipt(h.convTo!string.ox);
        if (a.isNull)
        {
            Nullable!TransactionReceipt tx;
            return tx;
        }

        return Nullable!TransactionReceipt(a.convTo!TransactionReceipt);
    }

    auto getTransaction(Hash txHash)
    {
        return eth_getTransactionByHash(txHash.convTo!string.ox).convTo!TransactionInfo;
    }

    Hash sendRawTransaction(Transaction tx)
    {
        import keccak : keccak256;
        import deth.util.types;

        bytes rlpTx = tx.serialize.rlpEncode;
        Hash hash = rlpTx.keccak256;
        auto signature = wallet[tx.from.get].sign(hash);

        ubyte v = cast(ubyte)(27 + signature.recid);

        auto rawTx = rlpEncode(tx.serialize ~ [v] ~ signature.r ~ signature.s).toHexString.ox;

        return eth_sendRawTransaction(rawTx).convTo!Hash;
    }

    Hash sendTransaction(Transaction tx)
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
        return eth_sendTransaction(jtx).convTo!Hash;
    }

    Address[] accounts()
    {
        return wallet.keys;
    }

    Address[] remoteAccounts()
    {
        return eth_accounts.map!(a => a.convTo!Address).array;
    }

    bool isUnlocked(Address addr)
    {
        return accounts.canFind(addr);
    }

    bool isUnlockedRemote(Address addr)
    {
        auto remoteAccounts = eth_accounts;
        return remoteAccounts.canFind(addr.convTo!string.ox);

    }
}

unittest
{
    auto conn = new RPCConnector("https://rpc.qtestnet.org:8545");
    auto pkValue = "beb75b08049e9316d1375999c7d968f3c23fdf606b296fcdfc9a41cdd7e7347c".hexToBytes;
    auto pk = new secp256k1(pkValue);
    conn.wallet[pk.address] = pk;
    import deth.util.decimals;

    Transaction tx = {
        from: pk.address, nonce: conn.getTransactionCount(pk.address), to: "0xdddddddd0d0d0d0d0d0d0ddddddddd"
            .convTo!Address, value: 16.wei, gas: "50000".BigInt, gasPrice: 50.gwei,
        data: cast(bytes) "\xdd\xdd\xdd\xdd Dlang - Fast code, fast."
    };
    Hash txHash;
    while (1)
    {
        import rpc.core : RpcException;

        try
        {
            txHash = conn.sendRawTransaction(tx);
            break;
        }
        catch (RpcException e)
        {
            import std.string : indexOf;

            if (!(e.msg.indexOf("invalid sender") >= 0))
            {
                throw e;
            }
        }
    }

    conn.getTransaction(txHash);
    while (conn.getTransaction(txHash).blockHash.isNull)
    {
        Thread.sleep(250.dur!"msecs");
    }
    assert(!conn.getTransactionReceipt(txHash).isNull);
}

unittest
{
    import std.stdio;

    writefln!"\033[1;32m%s\033[0m"(" rpc test passed. ");
}
