module deth.rpcconnector;

import std.digest : toHexString;
import std : Nullable;
import std.json : JSONValue;
import std.bigint;
import std.conv : to;
import std.range: chunks;
import std.algorithm: map;
import std.array: array;
import std.stdio;
import rpc.protocol.json;

import deth.util.types;


enum BlockNumber {
    EARLIEST = `earliest`,
    LATEST = `latest`,
    PENDING = `pending`
};

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
        assert(gas.isNull||gas.get >= 0);
        assert(gasPrice.isNull||gasPrice.get >= 0);
        assert(value.isNull||value.get >= 0);
    }

    JSONValue toJSON()
    {
        string[string] result;
        if(!from.isNull)
            result["from"] = from.get.toHexString.ox;
        if(!to.isNull)
            result["to"] = to.get.toHexString.ox;
        if(!gas.isNull)
            result["gas"] = gas.get.convTo!string.ox;
        if(!gasPrice.isNull)
            result["gasPrice"] = gasPrice.get.convTo!string.ox;
        if(!value.isNull)
            result["value"] = value.get.convTo!string.ox;
        if(!data.isNull)
            result["data"] = data.get.toHexString.ox;
        if(!nonce.isNull)
            result["nonce"] = nonce.get.to!string(16).ox;
        return result.JSONValue;
    }
}

interface IEthRPC
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

auto hexStringToUbytes(string t ){
    return t[2..$].chunks(2).map!"a.parse!ubyte(16)".array;
}

mixin template BlockNumberToJSON(){
    static if (is(BlockParameter==BlockNumber))
        JSONValue _block = block;
    else static if (is(BigInt == BlockParameter))
        JSONValue _block = block.convTo!string.ox;
    else static assert(0, "BlockParameter not support type " ~ stringof(BlockParameter));

}

class RPCConnector : HttpJsonRpcAutoClient!IEthRPC
{
    this(string url)
    {
        super(url);
    }
    BigInt eth_getBalance(BlockParameter)(ubyte[20] address, BlockParameter block)
    {
        mixin BlockNumberToJSON;
        return eth_getBalance(address.convTo!string.ox, block).BigInt;
    }
    ubyte[] eth_call(BlockParameter)(Transaction tx, BlockParameter block){
        mixin BlockNumberToJSON;
        return super.eth_call(tx.toJSON, _block).hexToBytes;
    };

    ulong eth_getTransactionCount(BlockParameter)(Address address, BlockParameter block){
        mixin BlockNumberToJSON;
        return eth_getTransactionCount(address.toHexString.ox, _block)[2..$].parse!ulong(16);
    }
}

unittest
{
    import std.stdio;
    import std.process : environment;

    auto host = environment.get("RPC_HOST", "127.0.0.1");
    IEthRPC conn = new RPCConnector("http://" ~ host ~ ":8545");
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
    conn.eth_getBalance(accounts[0], "latest".JSONValue).writeln;
    conn.eth_getBalance(accounts[0], 0.JSONValue).writeln;
    // conn. get storage at;
    conn.eth_getTransactionCount(accounts[0], "latest".JSONValue).writeln;
    conn.eth_getBlockTransactionCountByNumber("latest".JSONValue).writeln;
    conn.eth_sign(accounts[0], "0xaa1230fgD").writeln;
}
