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
    BigInt getBalance(BlockParameter)(ubyte[20] address, BlockParameter block = BlockNumber.LATEST)
    {
        mixin BlockNumberToJSON;
        return eth_getBalance(address.convTo!string.ox, _block).BigInt;
    }
    ubyte[] call(BlockParameter)(Transaction tx, BlockParameter block = BlockNumber.LATEST){
        mixin BlockNumberToJSON;
        return super.eth_call(tx.toJSON, _block)[2..$].hexToBytes;
    }

    ulong getTransactionCount(BlockParameter)(Address address, BlockParameter block = BlockNumber.LATEST){
        mixin BlockNumberToJSON;
        return eth_getTransactionCount(address.toHexString.ox, _block)[2..$].parse!ulong(16);
    }

    TransactionReceipt getTransactionReceipt(Hash h){
        JSONValue a = eth_getTransactionReceipt(h.convTo!string.ox);
        TransactionReceipt tx;
        tx.transactionIndex = a[`transactionIndex`].str[2..$].to!ulong(16);
        tx.from = a[`from`].str[2..$].convTo!Address;
        tx.blockHash = a[`from`].str[2..$].convTo!Hash;
        tx.blockNumber= a[`blockNumber`].str[2..$].to!ulong(16);
        if(!a[`to`].isNull)
            tx.to = a[`to`].str[2..$].convTo!Address;
        tx.cumulativeGasUsed = a[`cumulativeGasUsed`].str.BigInt;
        tx.gasUsed= a[`gasUsed`].str.BigInt;
        if(!a[`contractAddress`].isNull)
            tx.to = a[`contractAddress`].str[2..$].convTo!Address;
        tx.logsBloom = a[`logsBloom`].str[2..$].hexToBytes;
        tx.logs = new Log[a[`logs`].array.length];
        foreach(i, log; a[`logs`].array){
            tx.logs[i].removed  = log[`removed`].boolean;
            tx.logs[i].address = log[`address`].str[2..$].convTo!Address;
            tx.logs[i].data = log[`data`].str[2..$].hexToBytes;
            tx.logs[i].topics = [];
            foreach (topic; log[`topics`].array){
                tx.logs[i].topics ~= topic.str[2..$].convTo!Hash;
            }
        }
        return tx;
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
    // conn. get storage at;
    conn.eth_getTransactionCount(accounts[0], "latest".JSONValue).writeln;
    conn.eth_getBlockTransactionCountByNumber("latest".JSONValue).writeln;
    conn.eth_sign(accounts[0], "0xaa1230fgD").writeln;
}

struct TransactionReceipt{
    Hash transactionHash ;// DATA, 32 Bytes - hash of the transaction.
    ulong transactionIndex;// QUANTITY - integer of the transactions index position in the block.
    Hash blockHash;// DATA, 32 Bytes - hash of the block where this transaction was in.
    ulong blockNumber;// QUANTITY - block number where this transaction was in.
    Address from;// DATA, 20 Bytes - address of the sender.
    Nullable!Address to;// DATA, 20 Bytes - address of the receiver. null when its a contract creation transaction.
    BigInt cumulativeGasUsed ;// QUANTITY - The total amount of gas used when this transaction was executed in the block.
    BigInt gasUsed ;// QUANTITY - The amount of gas used by this specific transaction alone.
    Nullable!Address contractAddress ;// DATA, 20 Bytes - The contract address created, if the transaction was a contract creation, otherwise null.
    Log[] logs;// Array - Array of log objects, which this transaction generated.
    bytes logsBloom;// DATA, 256 Bytes - Bloom filter for light clients to quickly retrieve related logs.a
}

struct Log{
    bool removed;
    Address address; //  DATA, 20 Bytes - address from which this log originated.
    bytes data; //  DATA - contains one or more 32 Bytes non-indexed arguments of the log.
    Hash[] topics; //  Array of DATA - Array of 0 to 4 32 Bytes DATA of indexed log arguments. (In solidity; //  The first topic is the hash of the signature of the event (e.g. Deposit(address,bytes32,uint256)), except you declared the event with the anonymous specifier.)
}
