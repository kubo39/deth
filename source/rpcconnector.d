module rpcconnector;

import rpc.protocol.json;

interface IEthRPC {
    string web3_clientVersion();
    string web3_sha3(string data);
    string net_version();
    bool net_listening();
    int net_peerCount();
    string  eth_protocolVersion();
    // TODO: fix overloading
    //   string eth_getBalance(string address, ulong blockNumber);
    string eth_getBalance(string address, string tag);
}

alias RPCConnector = HttpJsonRpcAutoClient!IEthRPC;
