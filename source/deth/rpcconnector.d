module deth.rpcconnector;

import core.thread : Thread, dur;
import std.algorithm : map, canFind;
import std.array : array, replace, join;
import std.bigint;
import std.digest : toHexString;
import std.conv : to;
import std.exception : enforce;
import std.logger;
import std.json : JSONValue;
import std.sumtype;
import std.typecons : Nullable;

import deth.signer;
import deth.util;
import deth.util.transaction;
import deth.wallet : Wallet;

import rpc.protocol.json;
import rpc.core : IRpcClient, RpcInterfaceSettings, HttpRpcClient;
import secp256k1 : secp256k1;

enum BlockNumber
{
    EARLIEST = `earliest`,
    LATEST = `latest`,
    PENDING = `pending`,
    SAFE = `safe`,
    FINALIZED = `finalized`,
}

private interface IEthRPC
{
    string[] eth_accounts() @safe;
    string eth_blobBaseFee() @safe;
    string eth_blockNumber() @safe;
    string eth_call(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_chainId() @safe;
    string eth_coinbase() @safe;
    string eth_estimateGas(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_gasPrice() @safe;
    string eth_getBalance(string address, JSONValue blockNumber) @safe;
    JSONValue eth_getBlockByHash(string blockHash, bool isFull) @safe;
    JSONValue eth_getBlockByNumber(JSONValue blockNumber, bool isFull) @safe;
    string eth_getBlockTransactionCountByNumber(JSONValue blockNumber) @safe;
    string eth_getCode(string address, JSONValue blockNumber) @safe;
    JSONValue eth_getLogs(JSONValue filterOptions) @safe;
    string eth_getStorageAt(string address, string pos, JSONValue blockNumber) @safe;
    JSONValue eth_getTransactionByHash(string hash) @safe;
    JSONValue eth_getTransactionByBlockNumberAndIndex(JSONValue blockNumber, string index) @safe;
    string eth_getTransactionCount(string address, JSONValue blockNumber) @safe;
    JSONValue eth_getTransactionReceipt(string data) @safe;
    string eth_getUncleCountByBlockNumber(JSONValue blockNumber) @safe;
    string eth_hashrate() @safe;
    string eth_maxPriorityFeePerGas() @safe;
    bool eth_mining() @safe;
    JSONValue eth_getProof(string address, string[] storageKeys, JSONValue blockNumber) @safe;
    string eth_protocolVersion() @safe;
    string eth_sendTransaction(JSONValue tx) @safe;
    string eth_sendRawTransaction(string data) @safe;
    string eth_sign(string address, string data) @safe;
    string eth_signTransction(JSONValue tx) @safe;
    JSONValue eth_syncing() @safe;
    bool net_listening() @safe;
    int net_peerCount() @safe;
    string net_version() @safe;
    string web3_clientVersion() @safe;
    string web3_sha3(string data) @safe;
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
class RPCConnector : JsonRpcAutoAttributeClient!IEthRPC
{
    /// Alias for the RPC client type used by this connector
    protected alias RpcClient = IRpcClient!(int, JsonRpcRequest!int, JsonRpcResponse!int);

    /// Private keys stored by connector
    Wallet wallet;

    /// coeficient used for estimated gas
    uint gasEstimatePercentage = 100;

    /// Construct with a URL (creates HttpRpcClient internally)
    this(string url) @safe
    {
        super(new HttpRpcClient!(int, JsonRpcRequest!int, JsonRpcResponse!int)(url), new RpcInterfaceSettings());
    }

    /// Package constructor for injecting a custom RPC client (for testing)
    package this(RpcClient client) @safe
    {
        super(client, new RpcInterfaceSettings());
    }

    /// Wrapper for eth_getBalance
    /// Returns: count of native tokens on balance
    BigInt getBalance(BlockParameter)(Address address, BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return eth_getBalance(address.convTo!string.ox, _block).BigInt;
    }

    /// Wrapper for eth_estimateGas
    BigInt estimateGas(BlockParameter)(const Transaction tx, BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return super.eth_estimateGas(tx.toJSON, _block).BigInt;
    }

    /// Wrapper for eth_gasPrice
    BigInt gasPrice() @safe
    {
        return super.eth_gasPrice.BigInt;
    }

    /// Wrapper for eth_call
    /// Returns: encoded in bytes result of call
    ubyte[] call(BlockParameter)(Transaction tx, BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return super.eth_call(tx.toJSON, _block)[2 .. $].convTo!bytes;
    }

    /// wrapper for eth_getBlockByNumber
    /// Params:
    ///   isFull = if true, it returns the detail of each transaction.
    ///            If false, only the hashes of the transactions.
    /// Returns: block object, or null when no block was found.
    Nullable!BlockResponse getBlock(BlockParameter)(bool isFull,
        BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        JSONValue a = eth_getBlockByNumber(_block, isFull);
        Nullable!BlockResponse blockResponse;
        if (!a.isNull)
        {
            blockResponse = Nullable!BlockResponse(a.convTo!BlockResponse);
        }
        return blockResponse;
    }

    /// Wrapper for eth_getTrasactionCount
    /// Params:
    ///   address = address of user
    /// Returns: tx count
    ulong getTransactionCount(BlockParameter)(Address address,
        BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return eth_getTransactionCount(address.toHexString.ox, _block)[2 .. $].to!ulong(16);
    }

    /// Wrapper for eth_getTransactionReceipt
    /// Params:
    ///   h = hash of transaction
    /// Returns: TransactionReceipt if tx mined else null
    Nullable!TransactionReceipt getTransactionReceipt(Hash h) @safe
    {
        JSONValue a = eth_getTransactionReceipt(h.convTo!string.ox);
        Nullable!TransactionReceipt tx;
        if (!a.isNull)
        {
            tx = Nullable!TransactionReceipt(a.convTo!TransactionReceipt);
        }
        return tx;
    }

    auto getTransaction(Hash txHash) @safe
    {
        return eth_getTransactionByHash(txHash.convTo!string.ox).convTo!TransactionInfo;
    }

    /// Wrapper for eth_sendRawTransaction
    /// signs transaction and sends it
    /// signer is tx.from
    /// Params:
    ///   tx = Transaction wanted to be signed and sent
    /// Returns: Hash of transaction
    Hash sendRawTransaction(const Transaction tx) @safe
    {
        auto from = tx.getFrom();
        enforce(!from.isNull, "from is required for sendRawTransaction");
        auto signer = wallet.getSigner(from.get);
        auto rawTx = signer.signTransaction(tx);
        auto hash = eth_sendRawTransaction(rawTx.convTo!string.ox).convTo!Hash;
        tracef("sent tx %s", hash.convTo!string.ox);
        return hash;
    }

    /// Wrapper for method eth_sendTransaction
    /// Params:
    ///   tx = Transaction to send
    /// Returns: Hash of sended tx
    Hash sendTransaction(const Transaction tx) @safe
    {
        auto jtx = tx.toJSON();
        logf("Json string: %s", jtx.toString);
        auto hash = eth_sendTransaction(jtx).convTo!Hash;
        tracef("sent tx %s", hash.convTo!string.ox);
        return hash;
    }

    /// Wrapper for eth_getProof
    /// Params:
    ///   address = address of user
    ///   storageKeys = An array of 32-byte storage keys to be proofed and included
    /// Returns: EIP-1186 ProofResponse
    Nullable!ProofResponse getProof(BlockParameter)(Address address, string[] storageKeys,
        BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        JSONValue rawResponse = eth_getProof(address.convTo!string.ox, storageKeys, _block);
        Nullable!ProofResponse proofResponse;
        if (!rawResponse.isNull)
        {
            proofResponse = Nullable!ProofResponse(rawResponse.convTo!ProofResponse);
        }
        return proofResponse;
    }

    /// Wrapper for eth_getLogs.
    Nullable!LogsResponse getLogs(BlockParameter)(LogFilter!BlockParameter filter) @trusted
    {
        JSONValue jtx;
        if (!filter.from.isNull)
        {
            auto block = filter.from.get;
            mixin BlockNumberToJSON!block;
            jtx["from"] = _block;
        }
        if (!filter.to.isNull)
        {
            auto block = filter.to.get;
            mixin BlockNumberToJSON!block;
            jtx["to"] = _block;
        }
        if (!filter.address.isNull)
        {
            jtx["address"] = filter.address.get.convTo!string.ox;
        }
        if (!filter.topics.isNull)
            jtx["topics"] = filter.topics.get;
        JSONValue rawResponse = eth_getLogs(jtx);
        Nullable!LogsResponse logsResponse;
        if (rawResponse.isNull)
        {
            logsResponse = Nullable!LogsResponse(rawResponse.convTo!LogsResponse);
        }
        return logsResponse;
    }

    /// Returns: array with addresses which PK is stored in wallet
    Address[] accounts() const @safe
    {
        return wallet.addresses;
    }

    /// Wrapper for eth_accounts
    /// Returns: array with addresses which PK is stored on node
    Address[] remoteAccounts() @safe
    {
        return eth_accounts.map!(a => a.convTo!Address).array;
    }

    /// Checks if address is in wallet
    /// Params:
    ///   addr = address wanted to check
    /// Returns: true if address is in wallet and vice versa
    bool isUnlocked(Address addr) const @safe
    {
        return accounts.canFind(addr);
    }

    /// Checks if address is stored on node
    /// Params:
    ///   addr = address wanted to check
    /// Returns: true if address is stored on node and vice versa
    bool isUnlockedRemote(Address addr) @safe
    {
        return remoteAccounts.canFind(addr);
    }

    /// Wait tx to be mined to block
    /// Params:
    ///   txHash = hash of the transaction
    /// Returns: TransactionReceipt of mined transaction or throws an exception
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

    ///
    ulong chainId() @safe
    {
        return eth_chainId()[2 .. $].to!ulong(16);
    }

    ///
    BigInt maxPriorityFeePerGas() @safe
    {
        return eth_maxPriorityFeePerGas().BigInt;
    }

    ///
    BigInt blobBaseFee() @safe
    {
        return eth_blobBaseFee().BigInt;
    }
}


// Integration tests - require anvil running on localhost:8545
// Run with: dub test -- -d IntegrationTest
version (IntegrationTest)
{
    @("get latest block with the hashes of the transactions")
    unittest
    {
        auto conn = new RPCConnector("http://127.0.0.1:8545");
        const block = conn.getBlock(false);

        assert(!block.isNull);
        assert(block.get.size > 0);
    }

    @("sending legacy tx")
    unittest
    {
        import deth.util.decimals;

        auto conn = new RPCConnector("http://127.0.0.1:8545");

        const accounts = conn.remoteAccounts();
        const alice = accounts[0];
        const bob = accounts[1];

        // anvil's default private key.
        auto signer = new Signer(
            "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        );
        conn.wallet.addSigner(signer);

        LegacyTransaction legacyTx = {
            to: bob,
            value: 16.wei,
            data: cast(bytes) "\xdd\xdd\xdd\xdd Dlang - Fast code, fast.",
        };
        auto txHash = SendableLegacyTransaction(legacyTx, conn).send();
        conn.getTransaction(txHash);
        conn.waitForTransactionReceipt(txHash);
        assert(!conn.getTransactionReceipt(txHash).isNull);
    }

    @("sending eip-155 tx")
    unittest
    {
        import deth.util.decimals : wei;

        auto conn = new RPCConnector("http://127.0.0.1:8545");

        const accounts = conn.remoteAccounts();
        const alice = accounts[0];
        const bob = accounts[1];

        // anvil's default private key.
        auto signer = new Signer(
            "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        );
        conn.wallet.addSigner(signer);

        LegacyTransaction legacyTx = {
            to: bob,
            value: 16.wei,
            data: cast(bytes) "\xdd\xdd\xdd\xdd Dlang - Fast code, fast.",
            chainid: conn.net_version.to!ulong,
        };
        const txHash = SendableLegacyTransaction(legacyTx, conn).send();
        conn.getTransaction(txHash);
        conn.waitForTransactionReceipt(txHash);
        const receipt = conn.getTransactionReceipt(txHash);
        assert(!receipt.isNull);
        assert(receipt.get.from == alice);
        assert(receipt.get.to == bob);
    }

    @("sending eip-1559 transaction type 2")
    unittest
    {
        auto conn = new RPCConnector("http://127.0.0.1:8545");
        const accounts = conn.remoteAccounts();
        const alice = accounts[0];
        const bob = accounts[1];

        // anvil's default private key.
        auto signer = new Signer(
            "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        );
        conn.wallet.addSigner(signer);

        EIP1559Transaction eip1559tx = {
            from: alice,
            to: bob,
            value: 16.wei,
            data: cast(bytes) "\xdd\xdd\xdd\xdd Dlang - Fast code, fast.",
            chainid: conn.net_version.to!ulong,
            maxPriorityFeePerGas: 1.gwei,
            maxFeePerGas: 1.gwei + 20.wei,
        };
        SendableTransaction sendableTx = SendableEIP1559Transaction(eip1559tx, conn);
        const txHash = sendableTx.send();
        conn.getTransaction(txHash);
        conn.waitForTransactionReceipt(txHash);
        const receipt = conn.getTransactionReceipt(txHash);
        assert(!receipt.isNull);
        assert(receipt.get.from == alice);
        assert(receipt.get.to == bob);
        assert(receipt.get.type == TransactionType.EIP1559);
    }

    // https://eips.ethereum.org/EIPS/eip-1186
    @("eip-1186 merkle proofs")
    unittest
    {
        auto conn = new RPCConnector("http://127.0.0.1:8545");
        Address address = "0x7F0d15C7FAae65896648C8273B6d7E43f58Fa842".convTo!Address;
        auto storageKeys = [
            "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
        ];
        auto proof = conn.getProof(address, storageKeys);
        assert(proof.get.address == address);
    }

    // https://eips.ethereum.org/EIPS/eip-695
    @("eth_chainId")
    unittest
    {
        auto conn = new RPCConnector("http://127.0.0.1:8545");
        assert(conn.chainId() == 31337 /* anvil's default chain id */);
    }
}

// ============================================================================
// Mock-based Unit Tests
// ============================================================================

version (unittest)
{
    import core.time : Duration;
    import std.container : DList;
    import vibe.data.json : Json, parseJson;

    /// Mock RPC client for testing
    private class MockRpcClient : IRpcClient!(int, JsonRpcRequest!int, JsonRpcResponse!int)
    {
        alias Response = JsonRpcResponse!int;

        private DList!Response _responseQueue;
        private string[] _calledMethods;
        private size_t _queueSize = 0;

        void enqueueResponse(string jsonResult) @safe
        {
            auto response = new Response();
            response.result = parseJson(jsonResult);
            _responseQueue.insertBack(response);
            _queueSize++;
        }

        void enqueueError(int code, string message) @safe
        {
            auto response = new Response();
            auto error = new JsonRpcError();
            error.code = code;
            error.message = message;
            response.error = error;
            _responseQueue.insertBack(response);
            _queueSize++;
        }

        @property size_t requestCount() const @safe nothrow { return _calledMethods.length; }

        void assertMethodCalled(string method) const @safe
        {
            import std.algorithm : canFind;
            assert(_calledMethods.canFind(method), "Expected method '" ~ method ~ "' to be called");
        }

        // IRpcClient implementation
        @property bool connected() @safe nothrow { return true; }
        bool connect() @safe nothrow { return true; }
        void tick() @safe {}

        Response sendRequestAndWait(JsonRpcRequest!int request, Duration timeout = Duration.max()) @safe
        {
            _calledMethods ~= request.method;
            assert(_queueSize > 0, "No response queued for method '" ~ request.method ~ "'");
            auto response = _responseQueue.front;
            _responseQueue.removeFront();
            _queueSize--;
            response.id = request.id;
            return response;
        }
    }

    private string jsonHex(T)(T value) @safe pure
    {
        static if (is(T == BigInt))
            return "\"" ~ value.convTo!string.ox ~ "\"";
        else
            return "\"" ~ BigInt(value).convTo!string.ox ~ "\"";
    }
}

@("mock: chainId")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(31337UL));

    assert(conn.chainId() == 31337);
    mock.assertMethodCalled("eth_chainId");
}

@("mock: getBalance")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(BigInt("100000000000000000000")));

    Address addr;
    auto balance = conn.getBalance(addr);

    assert(balance == BigInt("100000000000000000000")); // 100 ETH in wei
    mock.assertMethodCalled("eth_getBalance");
}

@("mock: gasPrice")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(BigInt(20_000_000_000)));

    auto price = conn.gasPrice();

    assert(price == BigInt(20_000_000_000)); // 20 gwei
    mock.assertMethodCalled("eth_gasPrice");
}

@("mock: getTransactionCount")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(42UL));

    Address addr;
    auto count = conn.getTransactionCount(addr);

    assert(count == 42);
    mock.assertMethodCalled("eth_getTransactionCount");
}

@("mock: estimateGas")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(BigInt(21000)));

    LegacyTransaction tx;
    auto gas = conn.estimateGas(Transaction(tx));

    assert(gas == BigInt(21000));
    mock.assertMethodCalled("eth_estimateGas");
}

@("mock: call")
unittest
{
    import std.format : format;

    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    // 32 bytes with value 42 at the end
    mock.enqueueResponse(format!"\"0x%064x\""(42));

    LegacyTransaction tx;
    Transaction wrappedTx = tx;
    auto result = conn.call(wrappedTx);

    assert(result.length == 32);
    assert(result[31] == 42);
    mock.assertMethodCalled("eth_call");
}

@("mock: multiple RPC calls sequence")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(1UL));
    mock.enqueueResponse(jsonHex(5UL));
    mock.enqueueResponse(jsonHex(BigInt(30_000_000_000)));

    assert(conn.chainId() == 1);

    Address addr;
    assert(conn.getTransactionCount(addr) == 5);
    assert(conn.gasPrice() == BigInt(30_000_000_000));

    assert(mock.requestCount == 3);
}

@("mock: RPC error handling")
unittest
{
    import std.exception : assertThrown;
    import rpc.core : RpcException;

    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueError(-32000, "execution reverted");

    assertThrown!RpcException(conn.chainId());
}
