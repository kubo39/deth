module deth.rpcconnector;

import std.digest : toHexString;
import std.typecons : Nullable;
import std.json : JSONValue;
import std.bigint;
import std.conv : to;
import std.range : chunks;
import std.algorithm : map, canFind;
import std.array : array, join;
import std.stdio;
import std.sumtype;

import rpc.protocol.json;
import std.array : replace;
import deth.util.transaction;
import deth.wallet : Wallet;

import deth.util;
import secp256k1 : secp256k1;
import core.thread : Thread, dur, Fiber;
import std.exception : enforce;
import std.experimental.logger;

enum BlockNumber
{
    EARLIEST = `earliest`,
    LATEST = `latest`,
    PENDING = `pending`
}

private interface IEthRPC
{
    string web3_clientVersion() @safe;
    string web3_sha3(string data) @safe;
    string net_version() @safe;
    bool net_listening() @safe;
    int net_peerCount() @safe;
    string eth_protocolVersion() @safe;
    JSONValue eth_syncing() @safe;
    string eth_coinbase() @safe;
    bool eth_mining() @safe;
    string eth_hashrate() @safe;
    string eth_gasPrice() @safe;
    string[] eth_accounts() @safe;
    string eth_blockNumber() @safe;
    string eth_getBalance(string address, JSONValue blockNumber) @safe;
    string eth_getStorageAt(string address, string pos, JSONValue blockNumber) @safe;
    string eth_getTransactionCount(string address, JSONValue blockNumber) @safe;
    string eth_getBlockTransactionCountByNumber(JSONValue blockNumber) @safe;
    string eth_getUncleCountByBlockNumber(JSONValue blockNumber) @safe;
    string eth_getCode(string address, JSONValue blockNumber) @safe;
    string eth_sign(string address, string data) @safe;
    string eth_signTransction(JSONValue tx) @safe;
    string eth_sendTransaction(JSONValue tx) @safe;
    string eth_sendRawTransaction(string data) @safe;
    string eth_call(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_estimateGas(JSONValue tx, JSONValue blockNumber) @safe;
    string eth_chainId() @safe;
    JSONValue eth_getBlockByHash(string blockHash, bool isFull) @safe;
    JSONValue eth_getBlockByNumber(JSONValue blockNumber, bool isFull) @safe;
    JSONValue eth_getTransactionByHash(string hash) @safe;
    JSONValue eth_getTransactionByBlockNumberAndIndex(JSONValue blockNumber, string index) @safe;
    JSONValue eth_getTransactionReceipt(string data) @safe;
    JSONValue eth_getProof(string address, string[] storageKeys, JSONValue blockNumber) @safe;
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
    Wallet wallet;

    /// coeficient used for estimated gas
    uint gasEstimatePercentage = 100;

    this(string url) @safe
    {
        super(url);
    }

    /// Wrapper for eth_getBalance
    /// Returns: count of native tokens on balance
    BigInt getBalance(BlockParameter)(Address address, BlockParameter block = BlockNumber.LATEST) @safe
    {
        mixin BlockNumberToJSON!block;
        return eth_getBalance(address.convTo!string.ox, _block).BigInt;
    }

    /// Wrapper for eth_estimateGas
    BigInt estimateGas(BlockParameter)(Transaction tx, BlockParameter block = BlockNumber.LATEST) @safe
    {
        return tx.match!(
            (LegacyTransaction legacyTx) => estimateGas(legacyTx, block)
        );
    }

    BigInt estimateGas(BlockParameter)(LegacyTransaction tx, BlockParameter block = BlockNumber.LATEST) @safe
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
    /// signs transaction  and sends it
    /// signer is tx.from
    /// Params:
    ///   tx = Transaction wanted to be signed and sent
    /// Returns: Hash of transaction
    Hash sendRawTransaction(const Transaction tx) @safe
    {
        auto rawTx = wallet.signTransaction(tx);
        auto hash = eth_sendRawTransaction(rawTx.convTo!string.ox).convTo!Hash;
        tracef("sent tx %s", hash.convTo!string.ox);
        return hash;
    }

    ///
    Hash sendRawTransaction(const LegacyTransaction tx) @safe
    {
        auto rawTx = wallet.signTransaction(tx);
        auto hash = eth_sendRawTransaction(rawTx.convTo!string.ox).convTo!Hash;
        tracef("sent tx %s", hash.convTo!string.ox);
        return hash;
    }

    /// Wrapper for method eth_sendTransaction
    /// Params:
    ///   tx = Transaction to send
    /// Returns: Hash of sended tx
    Hash sendTransaction(Transaction tx) @safe
    {
        return tx.match!(
            (const LegacyTransaction legacyTx) => sendTransaction(legacyTx)
        );
    }

    ///
    Hash sendTransaction(const LegacyTransaction tx) @safe
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

    ulong chainId() @safe
    {
        return eth_chainId()[2 .. $].to!ulong(16);
    }
}


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
    conn.wallet.addPrivateKey(
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    );
    assert(conn.accounts[0] == alice);

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
    conn.wallet.addPrivateKey(
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    );
    assert(conn.accounts[0] == alice);

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

@("eth_chainId")
unittest
{
    auto conn = new RPCConnector("http://127.0.0.1:8545");
    assert(conn.chainId() == 31337 /* anvil's default chain id */);
}
