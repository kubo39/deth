module deth.rpcconnector;

import std.digest : toHexString;
import std : Nullable;
import std.json : JSONValue;
import std.bigint;
import std.conv : to;
import std.range : chunks;
import std.algorithm : map;
import std.array : array, join;
import std.stdio;
import rpc.protocol.json;
import std.array : replace;
import deth.rlp : rlpEncode, cutBytes;
import deth.util.types;
import secp256k1 : secp256k1;

enum BlockNumber
{
    EARLIEST = `earliest`,
    LATEST = `latest`,
    PENDING = `pending`
}

struct Transaction
{
    Nullable!Address from;
    Nullable!Address to;
    Nullable!BigInt gas;
    Nullable!BigInt gasPrice;
    Nullable!BigInt value;
    Nullable!bytes data = [];
    Nullable!ulong nonce;

    invariant
    {
        assert(gas.isNull || gas.get >= 0);
        assert(gasPrice.isNull || gasPrice.get >= 0);
        assert(value.isNull || value.get >= 0);
    }

    JSONValue toJSON()
    {
        string[string] result;
        if (!from.isNull)
            result["from"] = from.get.toHexString.ox;
        if (!to.isNull)
            result["to"] = to.get.toHexString.ox;
        if (!gas.isNull)
            result["gas"] = gas.get.convTo!string.ox;
        if (!gasPrice.isNull)
            result["gasPrice"] = gasPrice.get.convTo!string.ox;
        if (!value.isNull)
            result["value"] = value.get.convTo!string.ox;
        if (!data.isNull)
            result["data"] = data.get.toHexString.ox;
        if (!nonce.isNull)
            result["nonce"] = nonce.get.to!string(16).ox;
        return result.JSONValue;
    }

    bytes[] serialize()
    {
        bytes[] encoded = [];
        if (nonce.isNull)
            encoded ~= [[]];
        else
            encoded ~= cutBytes(cast(bytes)[nonce.get]);

        static immutable code = q{
            if(field.isNull)
                encoded ~= [[]];
            else
                encoded ~= field.get.convTo!bytes;
        };
        static foreach (field; ["gasPrice", "gas", "to", "value"])
        {
            mixin(code.replace("field", field));
        }
        encoded ~= data.get;
        return encoded;
    }
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
        return super.eth_call(tx.toJSON, _block)[2 .. $].hexToBytes;
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
        import keccak : keccak_256;
        import deth.util.types;

        bytes rlpTx = tx.serialize.rlpEncode;
        Hash hash;
        keccak_256(hash.ptr, hash.length, rlpTx.ptr, rlpTx.length);
        auto signature = wallet[tx.from.get].sign(hash);

        ubyte v = cast(ubyte)(27 + signature.recid);
        v.writeln;

        auto rawTx = rlpEncode(tx.serialize ~ [v] ~ signature.r ~ signature.s).toHexString.ox;

        return eth_sendRawTransaction(rawTx).convTo!Hash;
    }

    Hash sendTransaction(Transaction tx)
    {
        JSONValue jtx = [
            "from": tx.from.get.convTo!string.ox,
            "value": tx.value.get.convTo!string.ox,
            "to": tx.to.get.convTo!string.ox
        ];
        return eth_sendTransaction(jtx).convTo!Hash;
    }
}

unittest
{
    import std.stdio;
    import std.process : environment;

    auto host = environment.get("RPC_HOST", "127.0.0.1");
    auto conn = new RPCConnector("http://" ~ host ~ ":8545");
    conn.web3_clientVersion.writeln;
    conn.web3_sha3("0x1234t66");
    conn.net_version.writeln;
    conn.net_listening.writeln;
    conn.net_peerCount.writeln;
    conn.eth_protocolVersion.writeln;
    conn.eth_syncing.writeln;
    conn.eth_mining.writeln;
    conn.eth_hashrate.writeln;
    conn.eth_gasPrice.writeln;
    auto accounts = conn.eth_accounts;
    accounts.writeln;
    conn.eth_blockNumber.writeln;
    conn.getBalance("123".convTo!Address).writeln;
    conn.eth_getBalance(accounts[0], "latest".JSONValue).writeln;
    conn.eth_getBalance(accounts[0], 0.JSONValue).writeln;
    conn.eth_getTransactionCount(accounts[0], "latest".JSONValue).writeln;
    conn.eth_getBlockTransactionCountByNumber("latest".JSONValue).writeln;
    conn.eth_sign(accounts[0], "0xaa1230fgD").writeln;

}

unittest
{
    auto conn = new RPCConnector("http://35.161.73.158:8545");
    writeln("tx serialization");
    auto pkValue = "beb75b08049e9316d1375999c7d968f3c23fdf606b296fcdfc9a41cdd7e7347c".hexToBytes;
    auto pk = new secp256k1(pkValue);
    conn.wallet[pk.address] = pk;

    Transaction tx = {
        from: pk.address, nonce: conn.getTransactionCount(pk.address), to: "0x0123".convTo!Address, value: "0x123"
            .BigInt, gas: "50000".BigInt, gasPrice: "10000".BigInt, data: []
    };
    auto txHash = conn.sendRawTransaction(tx);
    import core.thread : Thread, dur;

    conn.getTransaction(txHash).writeln;
    Thread.sleep(10.dur!"seconds");
    conn.getTransactionReceipt(txHash).get.writeln;
}
