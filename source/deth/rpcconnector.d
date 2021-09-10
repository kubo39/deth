module deth.rpcconnector;

import std:Nullable;
import std.json: JSONValue;
import rpc.protocol.json;

struct Transaction {
    string from;
    Nullable!string to;
    Nullable!ulong gas;
    Nullable!ulong gasPrice;
    Nullable!ulong value;
    string data = "0x";
    Nullable!ulong nonce;
}

interface IEthRPC {
    string web3_clientVersion();
    string web3_sha3(string data);
    string net_version();
    bool net_listening();
    int net_peerCount();
    string  eth_protocolVersion();
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
    string eth_getUncleCountByBlockHash(string);
    string eth_getUncleCountByBlockNumber(JSONValue blockNumber);
    string eth_getCode(string address, JSONValue blockNumber);
    string eth_sign(string address, string data);
    string eth_signTransction(Transaction tx); 
    string eth_sendTransaction(Transaction tx);
    string eth_sendRawTransaction(string data);
    string eth_call(Transaction tx, JSONValue blockNumber);
    string eth_estimateGas(Transaction tx, JSONValue blockNumber);
    // TODO make struct for block info 
    JSONValue eth_getBlockByHash(string blockHash, bool isFull);
    JSONValue eth_getBlockByNumber(JSONValue blockNumber, bool isFull);
    JSONValue eth_getTransactionByHash(string hash);
    JSONValue eth_getTransactionByBlockNumberAndIndex(
            JSONValue blockNumber, string index
    );

    JSONValue eth_getTransactionReceipt(string data);
}

alias RPCConnector = HttpJsonRpcAutoClient!IEthRPC;

