module rpcconnector;

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
    string eth_getBalance(string address, JSONValue blockNumber);
    string eth_coinbase();
    bool eth_mining();
    string eth_hashrate();
    string[] eth_accounts();
    string eth_sendTransaction(Transaction transaction);
    JSONValue eth_getTransactionReceipt(string data);
}

alias RPCConnector = HttpJsonRpcAutoClient!IEthRPC;

