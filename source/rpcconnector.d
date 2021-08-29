module rpcconnector;

import rpc.protocol.json;

interface IEthRPC {
    string web3_clientVersion();
}

alias RPCConnector = HttpJsonRpcAutoClient!IEthRPC;
