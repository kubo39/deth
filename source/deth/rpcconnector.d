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

import deth.filterwatcher;
import deth.signer;
import deth.util;
import deth.util.transaction;
import deth.wallet : Wallet;

import rpc.protocol.json;
import rpc.core : IRpcClient, RpcInterfaceSettings, HttpRpcClient;
import secp256k1 : secp256k1;

///
enum BlockNumber
{
    EARLIEST = `earliest`,
    LATEST = `latest`,
    PENDING = `pending`,
    SAFE = `safe`,
    FINALIZED = `finalized`,
}

// https://ethereum.github.io/execution-apis/
private interface IEthRPC
{
    JSONValue debug_getBadBlocks() @safe;
    string debug_getRawBlock(JSONValue blockNumber) @safe;
    string debug_getRawHeader(JSONValue blockNumber) @safe;
    string[] debug_getRawReceipts(JSONValue blockNumber) @safe;
    string debug_getRawTransaction(string data) @safe;

    string[] eth_accounts() @safe;
    string eth_blobBaseFee() @safe;
    string eth_blockNumber() @safe;
    string eth_call(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_chainId() @safe;
    string eth_coinbase() @safe;
    JSONValue eth_createAccessList(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_estimateGas(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_gasPrice() @safe;
    string eth_getBalance(string address, JSONValue blockNumber) @safe;
    JSONValue eth_getBlockByHash(string blockHash, bool isFull) @safe;
    JSONValue eth_getBlockByNumber(JSONValue blockNumber, bool isFull) @safe;
    JSONValue eth_getBlockReceipts(JSONValue blockNumber) @safe;
    string eth_getBlockTransactionCountByHash(string blockHash) @safe;
    string eth_getBlockTransactionCountByNumber(JSONValue blockNumber) @safe;
    string eth_getCode(string address, JSONValue blockNumber) @safe;
    JSONValue eth_getFilterChanges(string filter) @safe;
    JSONValue eth_getFilterLogs(string filter) @safe;
    JSONValue eth_getLogs(JSONValue filterOptions) @safe;
    JSONValue eth_getProof(string address, string[] storageKeys, JSONValue blockNumber) @safe;
    string eth_getStorageAt(string address, string pos, JSONValue blockNumber) @safe;
    JSONValue eth_getTransactionByBlockHashAndIndex(string blockHash, string index) @safe;
    JSONValue eth_getTransactionByBlockNumberAndIndex(JSONValue blockNumber, string index) @safe;
    JSONValue eth_getTransactionByHash(string hash) @safe;
    string eth_getTransactionCount(string address, JSONValue blockNumber) @safe;
    JSONValue eth_getTransactionReceipt(string data) @safe;
    string eth_getUncleCountByBlockHash(string blockHash) @safe;
    string eth_getUncleCountByBlockNumber(JSONValue blockNumber) @safe;
    string eth_hashrate() @safe;
    string eth_maxPriorityFeePerGas() @safe;
    bool eth_mining() @safe;
    string eth_newBlockFilter() @safe;
    string eth_newFilter(JSONValue filter) @safe;
    string eth_newPendingTransactionFilter() @safe;
    string eth_protocolVersion() @safe;
    string eth_sendTransaction(JSONValue tx) @safe;
    string eth_sendRawTransaction(string data) @safe;
    string eth_sign(string address, string data) @safe;
    string eth_signTransction(JSONValue tx) @safe;
    JSONValue eth_syncing() @safe;
    bool eth_uninstallFilter(string filter) @safe;
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
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_getLogs/
    Nullable!LogsResponse getLogs(BlockParameter)(LogFilter!BlockParameter filter) @trusted
    {
        JSONValue jtx;
        if (!filter.from.isNull)
        {
            const block = filter.from.get;
            mixin BlockNumberToJSON!block;
            jtx["fromBlock"] = _block;
        }
        if (!filter.to.isNull)
        {
            const block = filter.to.get;
            mixin BlockNumberToJSON!block;
            jtx["toBlock"] = _block;
        }
        if (!filter.address.isNull)
        {
            jtx["address"] = filter.address.get.convTo!string.ox;
        }
        if (!filter.topics.isNull)
            jtx["topics"] = filter.topics.get;
        JSONValue rawResponse = eth_getLogs(jtx);
        Nullable!LogsResponse logsResponse;
        if (!rawResponse.isNull)
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
    TransactionReceipt waitForTransactionReceipt(Hash txHash, ulong confirmations = 1) @safe
    {
        enforce(confirmations >= 1, "confirmations must be at least 1");
        ulong count;
        while (getTransaction(txHash).blockHash.isNull)
        {
            enforce(count < 500, "Timeout for waiting tx"); // TODO: add timeout into connector
            () @trusted { Thread.sleep(200.dur!"msecs"); }();
            count++;
        }
        auto receipt = getTransactionReceipt(txHash).get;

        if (confirmations > 1)
        {
            ulong confirmCount;
            while (true)
            {
                enforce(confirmCount < 500, "Timeout for waiting confirmations");
                auto currentBlock = eth_blockNumber()[2 .. $].to!ulong(16);
                if (currentBlock >= receipt.blockNumber + confirmations - 1)
                    break;
                () @trusted { Thread.sleep(200.dur!"msecs"); }();
                confirmCount++;
            }
        }

        return receipt;
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

    /// Wrapper for eth_newFilter.
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_newFilter/
    FilterID newFilter(BlockParameter)(LogFilter!BlockParameter filter) @trusted
    {
        JSONValue jtx;
        if (!filter.from.isNull)
        {
            const block = filter.from.get;
            mixin BlockNumberToJSON!block;
            jtx["fromBlock"] = _block;
        }
        if (!filter.to.isNull)
        {
            const block = filter.to.get;
            mixin BlockNumberToJSON!block;
            jtx["toBlock"] = _block;
        }
        if (!filter.address.isNull)
        {
            jtx["address"] = filter.address.get.convTo!string.ox;
        }
        if (!filter.topics.isNull)
            jtx["topics"] = filter.topics.get;
        return FilterID(eth_newFilter(jtx));
    }

    /// Wrapper for eth_getFilterChanges.
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_getFilterChanges/
    Log[] getFilterChanges(FilterID filterID) @trusted
    {
        JSONValue rawResponse = eth_getFilterChanges(filterID.id);
        if (rawResponse.isNull)
            return [];
        return rawResponse.convTo!LogsResponse.get;
    }

    /// Wrapper for eth_getFilterLogs.
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_getFilterLogs/
    Log[] getFilterLogs(FilterID filterID) @trusted
    {
        JSONValue rawResponse = eth_getFilterLogs(filterID.id);
        if (rawResponse.isNull)
            return [];
        return rawResponse.convTo!LogsResponse.get;
    }

    /// Wrapper for eth_getFilterChanges (block/pending tx filter variant).
    /// Returns Hash[] instead of Log[] for block and pending transaction filters.
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_getFilterChanges/
    Hash[] getFilterChangesHashes(FilterID filterID) @trusted
    {
        JSONValue rawResponse = eth_getFilterChanges(filterID.id);
        if (rawResponse.isNull)
            return [];
        return () @trusted {
            return rawResponse.array
                .map!(h => h.str.convTo!Hash)
                .array;
        }();
    }

    /// Wrapper for eth_uninstallFilter.
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_uninstallFilter/
    bool uninstallFilter(FilterID filterID) @safe
    {
        return eth_uninstallFilter(filterID.id);
    }

    /// Wrapper for eth_newBlockFilter.
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_newBlockFilter/
    FilterID newBlockFilter() @safe
    {
        return FilterID(eth_newBlockFilter());
    }

    /// Wrapper for eth_newPendingTransactionFilter.
    ///
    /// https://ethereum.github.io/execution-apis/api/methods/eth_newPendingTransactionFilter/
    FilterID newPendingTransactionFilter() @safe
    {
        return FilterID(eth_newPendingTransactionFilter());
    }

    /// Creates a LogFilterWatcher for polling log changes.
    /// Internally calls eth_newFilter and returns a watcher
    /// whose getChanges() returns Log[].
    LogFilterWatcher watchLogs(BlockParameter)(LogFilter!BlockParameter filter) @trusted
    {
        auto filterID = newFilter(filter);
        return LogFilterWatcher(this, filterID);
    }

    /// Creates a BlockFilterWatcher for polling new blocks.
    /// Internally calls eth_newBlockFilter and returns a watcher
    /// whose getChanges() returns Hash[].
    BlockFilterWatcher watchBlocks() @safe
    {
        auto filterID = newBlockFilter();
        return BlockFilterWatcher(this, filterID);
    }

    /// Creates a PendingTxFilterWatcher for polling pending transactions.
    /// Internally calls eth_newPendingTransactionFilter and returns a watcher
    /// whose getChanges() returns Hash[].
    PendingTxFilterWatcher watchPendingTransactions() @safe
    {
        auto filterID = newPendingTransactionFilter();
        return PendingTxFilterWatcher(this, filterID);
    }
}

private:

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
        const proof = conn.getProof(address, storageKeys);
        assert(proof.get.address == address);
    }

    // https://eips.ethereum.org/EIPS/eip-695
    @("eth_chainId")
    unittest
    {
        auto conn = new RPCConnector("http://127.0.0.1:8545");
        assert(conn.chainId() == 31_337 /* anvil's default chain id */);
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

        ///
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

    mock.enqueueResponse(jsonHex(31_337UL));

    assert(conn.chainId() == 31_337);
    mock.assertMethodCalled("eth_chainId");
}

@("mock: getBalance")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(BigInt("100000000000000000000")));

    Address addr;
    const balance = conn.getBalance(addr);

    assert(balance == BigInt("100000000000000000000")); // 100 ETH in wei
    mock.assertMethodCalled("eth_getBalance");
}

@("mock: gasPrice")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(BigInt(20_000_000_000)));

    const price = conn.gasPrice();

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
    const count = conn.getTransactionCount(addr);

    assert(count == 42);
    mock.assertMethodCalled("eth_getTransactionCount");
}

@("mock: estimateGas")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(BigInt(21_000)));

    LegacyTransaction tx;
    const gas = conn.estimateGas(Transaction(tx));

    assert(gas == BigInt(21_000));
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

@("mock: blobBaseFee")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(jsonHex(BigInt(1_000_000_000)));

    auto fee = conn.blobBaseFee();

    assert(fee == BigInt(1_000_000_000)); // 1 gwei
    mock.assertMethodCalled("eth_blobBaseFee");
}

@("mock: RPC error handling")
unittest
{
    import std.exception : assertThrown;
    import rpc.core : RpcException;

    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueError(-32_000, "execution reverted");

    assertThrown!RpcException(conn.chainId());
}

@("mock: newFilter")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`"0x1"`);

    LogFilter!BlockNumber filter;
    filter.from = BlockNumber.LATEST;
    auto filterID = conn.newFilter(filter);

    assert(filterID.id == "0x1");
    mock.assertMethodCalled("eth_newFilter");
}

@("mock: getFilterChanges returns logs")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`[{
        "removed": false,
        "logIndex": "0x0",
        "transactionIndex": "0x0",
        "transactionHash": "0x0000000000000000000000000000000000000000000000000000000000000001",
        "blockHash": "0x0000000000000000000000000000000000000000000000000000000000000002",
        "blockTimestamp": "0x0",
        "address": "0x0000000000000000000000000000000000000001",
        "data": "0x0000000000000000000000000000000000000000000000000000000000000064",
        "topics": [
            "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
        ]
    }]`);

    auto logs = conn.getFilterChanges(FilterID("0x1"));
    assert(logs.length == 1);
    assert(!logs[0].removed);
    mock.assertMethodCalled("eth_getFilterChanges");
}

@("mock: getFilterChanges returns empty")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`[]`);

    auto logs = conn.getFilterChanges(FilterID("0x1"));
    assert(logs.length == 0);
    mock.assertMethodCalled("eth_getFilterChanges");
}

@("mock: uninstallFilter")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`true`);

    assert(conn.uninstallFilter(FilterID("0x1")));
    mock.assertMethodCalled("eth_uninstallFilter");
}

@("mock: newBlockFilter")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`"0x2"`);

    auto filterID = conn.newBlockFilter();
    assert(filterID.id == "0x2");
    mock.assertMethodCalled("eth_newBlockFilter");
}

@("mock: newPendingTransactionFilter")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`"0x3"`);

    auto filterID = conn.newPendingTransactionFilter();
    assert(filterID.id == "0x3");
    mock.assertMethodCalled("eth_newPendingTransactionFilter");
}

@("mock: getFilterChangesHashes returns hashes")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`[
        "0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000000000000000000000000000002"
    ]`);

    auto hashes = conn.getFilterChangesHashes(FilterID("0x1"));
    assert(hashes.length == 2);
    assert(hashes[0][31] == 1);
    assert(hashes[1][31] == 2);
    mock.assertMethodCalled("eth_getFilterChanges");
}

@("mock: getFilterChangesHashes returns empty")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    mock.enqueueResponse(`[]`);

    auto hashes = conn.getFilterChangesHashes(FilterID("0x1"));
    assert(hashes.length == 0);
}

@("mock: watchLogs creates watcher and getChanges returns logs")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    // newFilter response
    mock.enqueueResponse(`"0x1"`);
    // getFilterChanges response
    mock.enqueueResponse(`[{
        "removed": false,
        "logIndex": "0x0",
        "transactionIndex": "0x0",
        "transactionHash": "0x0000000000000000000000000000000000000000000000000000000000000001",
        "blockHash": "0x0000000000000000000000000000000000000000000000000000000000000002",
        "blockTimestamp": "0x0",
        "address": "0x0000000000000000000000000000000000000001",
        "data": "0x",
        "topics": []
    }]`);
    // uninstallFilter response
    mock.enqueueResponse(`true`);

    LogFilter!BlockNumber filter;
    filter.from = BlockNumber.LATEST;
    auto watcher = conn.watchLogs(filter);

    assert(watcher.active);
    assert(watcher.filter.id == "0x1");

    auto logs = watcher.getChanges();
    assert(logs.length == 1);

    watcher.stop();
    assert(!watcher.active);
}

@("mock: watchBlocks creates watcher and getChanges returns hashes")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    // newBlockFilter response
    mock.enqueueResponse(`"0x2"`);
    // getFilterChanges response
    mock.enqueueResponse(`[
        "0x0000000000000000000000000000000000000000000000000000000000000abc"
    ]`);
    // uninstallFilter response
    mock.enqueueResponse(`true`);

    auto watcher = conn.watchBlocks();

    assert(watcher.active);
    auto hashes = watcher.getChanges();
    assert(hashes.length == 1);

    watcher.stop();
    assert(!watcher.active);
}

@("mock: watchPendingTransactions creates watcher and getChanges returns hashes")
unittest
{
    auto mock = new MockRpcClient();
    auto conn = new RPCConnector(mock);

    // newPendingTransactionFilter response
    mock.enqueueResponse(`"0x3"`);
    // getFilterChanges response
    mock.enqueueResponse(`[]`);
    // uninstallFilter response
    mock.enqueueResponse(`true`);

    auto watcher = conn.watchPendingTransactions();

    assert(watcher.active);
    auto hashes = watcher.getChanges();
    assert(hashes.length == 0);

    watcher.stop();
    assert(!watcher.active);
}
