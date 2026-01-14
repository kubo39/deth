module deth.util.types;

import std.algorithm : map;
import std.array : array;
import std.bigint : BigInt;
import std.bitmanip : nativeToBigEndian;
import std.conv : to;
import std.digest : toHexStringT = toHexString, LetterCase;
import std.json : JSONValue;
import std.typecons : Nullable;

alias toHexString = toHexStringT!(LetterCase.lower);

alias Address = ubyte[20];
alias Hash = ubyte[32];
alias bytes = ubyte[];

bytes hexToBytes(string s) @safe pure
{
    import std.algorithm : map, startsWith;
    import std.array : array;
    import std.range : chunks, padLeft;

    if (s.startsWith(`0x`))
        s = s[2 .. $];

    return s.padLeft('0', s.length + s.length % 2)
        .chunks(2)
        .map!q{a.parse!ubyte(16)}
        .array;
}

string toHex(const(BigInt) x) @safe pure
{
    import std.array : appender;
    auto outbuff = appender!string();
    x.toString(outbuff, "%X");
    return outbuff[];
}

@("hexToBytes")
unittest
{
    assert("0x123".hexToBytes == [0x1, 0x23]);
}

To convTo(To, _From)(const _From f) @safe pure
{
    import std.traits : Unconst, isIntegral;

    alias From = Unconst!_From;
    static if (is(From == bytes) || is(From == const(ubyte)[]))
    {
        static if (is(To == string))
        {
            return f.toHexString;
        }
    }
    static if (isIntegral!From)
    {
        static if (is(To == bytes))
        {
            return f.nativeToBigEndian[].dup;
        }
    }

    static if (is(From == Address))
    {
        static if (is(To == string))
        {
            return f.toHexString.to!string;
        }
        static if (is(To == bytes))
        {
            return (cast(bytes) f.dup);
        }
    }
    static if (is(From == Hash))
    {
        static if (is(To == string))
        {
            return f.toHexString.to!string;
        }
        static if (is(To == bytes))
        {
            return f[];
        }
    }
    // BigInt Part
    import std.bigint : BigInt;

    static if (is(From == BigInt))
    {
        static if (is(To == bytes))
        {
            import std.array : replace;
            import std.range : chunks, padLeft;

            auto hex = f.toHex.replace("_", "");
            return hex.padLeft('0', hex.length + hex.length % 2).to!string.hexToBytes;
        }
        static if (is(To == string))
        {
            import std.array;

            return f.toHex.replace("_", "");

        }
    }
    static if (is(From == string))
    {
        static if (is(To == Address))
        {
            Address v = f.hexToBytes().padLeft(0, 20)[0..20];
            return v;
        }
        static if (is(To == Hash))
        {
            Hash v = f.hexToBytes().padLeft(0, 32)[0..32];
            return v;
        }
        static if (is(To == bytes))
        {
            return f.hexToBytes;
        }
    }
    static if (is(From == JSONValue))
    {
        static if (is(To == BlockResponse))
        {
            BlockResponse blk;
            () @trusted {
                if (!f[`number`].isNull)
                    blk.number = f[`number`].str[2 .. $].to!ulong(16);
                if (!f[`hash`].isNull)
                    blk.hash = f[`hash`].str[2 .. $].convTo!Hash;
                if (!f[`parentHash`].isNull)
                    blk.parentHash = f[`parentHash`].str[2 .. $].convTo!Hash;
                blk.nonce = f[`nonce`].str[2 .. $].to!ulong(16);
                blk.sha3Uncles = f[`sha3Uncles`].str[2 .. $].convTo!Hash;
                if (!f[`logsBloom`].isNull)
                    blk.logsBloom = f[`logsBloom`].str[2 .. $].hexToBytes;
                blk.transactionsRoot = f[`transactionsRoot`].str[2 .. $].convTo!Hash;
                blk.stateRoot = f[`stateRoot`].str[2 .. $].convTo!Hash;
                blk.receiptsRoot = f[`receiptsRoot`].str[2 .. $].convTo!Hash;
                blk.miner = f[`miner`].str[2 .. $].convTo!Address;
                if (const difficulty = `difficulty` in f)
                    blk.difficulty = difficulty.str.BigInt;
                if (const totalDifficulty = `totalDifficulty` in f)
                    blk.totalDifficulty = totalDifficulty.str.BigInt;
                blk.extraData = f[`extraData`].str[2 .. $].hexToBytes;
                blk.size = f[`size`].str[2 .. $].to!ulong(16);
                blk.gasLimit = f[`gasLimit`].str.BigInt;
                blk.gasUsed = f[`gasUsed`].str.BigInt;
                blk.timestamp = f[`timestamp`].str.BigInt;
                blk.transactions = new bytes[f[`transactions`].array.length];
                foreach (i, transaction; f[`transactions`].array)
                {
                    blk.transactions[i] = transaction.str[2 .. $].hexToBytes;
                }
                blk.uncles = new Hash[f[`uncles`].array.length];
                foreach (i, uncleHash; f[`uncles`].array)
                {
                    blk.uncles[i] = uncleHash.str[2 .. $].convTo!Hash;
                }
            }();
            return blk;
        }
        static if (is(To == TransactionReceipt))
        {
            TransactionReceipt tx;
            () @trusted {
                tx.transactionIndex = f[`transactionIndex`].str[2 .. $].to!ulong(16);
                tx.from = f[`from`].str[2 .. $].convTo!Address;
                tx.blockHash = f[`blockHash`].str[2 .. $].convTo!Hash;
                tx.blockNumber = f[`blockNumber`].str[2 .. $].to!ulong(16);
                if (!f[`to`].isNull)
                    tx.to = f[`to`].str[2 .. $].convTo!Address;
                tx.cumulativeGasUsed = f[`cumulativeGasUsed`].str.BigInt;
                tx.gasUsed = f[`gasUsed`].str.BigInt;
                if (!f[`contractAddress`].isNull)
                    tx.contractAddress = f[`contractAddress`].str[2 .. $].convTo!Address;
                tx.logsBloom = f[`logsBloom`].str[2 .. $].hexToBytes;
                tx.logs = new Log[f[`logs`].array.length];
                foreach (i, log; f[`logs`].array)
                {
                    tx.logs[i].removed = log[`removed`].boolean;
                    tx.logs[i].address = log[`address`].str[2 .. $].convTo!Address;
                    tx.logs[i].data = log[`data`].str[2 .. $].hexToBytes;
                    tx.logs[i].topics = [];
                    foreach (topic; log[`topics`].array)
                    {
                        tx.logs[i].topics ~= topic.str[2 .. $].convTo!Hash;
                    }
                }
                if (!f[`type`].isNull)
                    tx.type = f[`type`].str[2 .. $].to!ulong(16);
            }();
            return tx;
        }
        static if (is(To == TransactionInfo))
        {
            TransactionInfo info;
            ()@trusted {
                if (!f[`to`].isNull)
                    info.to = f[`to`].str.convTo!Address;
                if (`blockNumber` in f && !f[`blockNumber`].isNull)
                {
                    info.blockHash = f[`blockHash`].str.convTo!Hash;
                    info.blockNumber = f[`blockNumber`].str[2 .. $].to!ulong(16);
                    info.transactionIndex = f[`transactionIndex`].str[2 .. $].to!ulong(16);

                }

                info.from = f[`from`].str.convTo!Address;
                info.input = f[`input`].str.convTo!bytes;

                info.gas = f[`gas`].str.BigInt;
                info.gasPrice = f[`gasPrice`].str.BigInt;
                info.value = f[`value`].str.BigInt;

                info.nonce = f[`nonce`].str[2 .. $].to!ulong(16);

                info.v = f[`v`].str[2 .. $].to!ulong(16);
                info.r = f[`r`].str.convTo!Hash;
                info.s = f[`s`].str.convTo!Hash;
            }();
            return info;
        }
        static if(is(To == ProofResponse))
        {
            ProofResponse proof;
            () @trusted {
                proof.address = f[`address`].str.convTo!Address;

                if (!f[`accountProof`].isNull)
                    proof.accountProof = f[`accountProof`].array
                        .map!(a => a.str[2 .. $].hexToBytes)
                        .array;

                proof.balance = f[`balance`].str.BigInt;
                proof.codeHash = f[`codeHash`].str.convTo!Hash;
                proof.nonce = f[`nonce`].str[2 .. $].to!ulong(16);

                if (!f[`storageProof`].isNull)
                {
                    proof.storageProof = f[`storageProof`].array
                        .map!(elem => StorageProof(
                            elem[`key`].str.convTo!bytes,
                            elem[`value`].str.convTo!bytes,
                            elem[`proof`].array
                                .map!(a => a.str[2 .. $].hexToBytes)
                                .array
                        ))
                        .array;
                }

                proof.storageHash = f[`storageHash`].str.convTo!Hash;
            }();
            return proof;
        }
    }
}

@("convTo")
unittest
{
    import std.string : join;
    import std.range : iota;

    ///looks like big endian coding
    bytes becodedNum = [15, 255, 255, 255, 255, 170];
    assert(`0xfffffffffaa`.BigInt.convTo!bytes == becodedNum);

    Address addr;
    assert(addr.convTo!string == 20.iota.array.map!q{"00"}.join);

    enum T
    {
        A,
        B
    }

    assert(!__traits(compiles, addr.convTo!T), `shouldn't compile with undefined conv pair`);
}

auto ox(T)(const T t) pure @safe 
{
    return `0x` ~ t[];
}

bytes padLeft(const bytes data, ubyte b, ulong count) pure @safe 
{
    if (count > data.length)
    {
        auto pad = new ubyte[count - data.length];
        pad[] = b;
        return pad ~ data;
    }
    else
        return data.dup;
}

bytes padRight(const bytes data, ubyte b, ulong count) pure @safe
{
    if (count > data.length)
    {
        auto pad = new ubyte[count - data.length];
        pad[] = b;
        return data ~ pad;
    }
    else
        return data.dup;
}

@("0x prefix")
unittest
{
    assert("0x123" == `123`.ox);
    char[4] t;
    t[] = 'a';
    assert(t.ox == "0xaaaa");
}

struct BlockResponse
{
    Nullable!ulong number;
    Nullable!Hash hash;
    Nullable!Hash parentHash;
    ulong nonce;
    Hash sha3Uncles;
    Nullable!bytes logsBloom;
    Hash transactionsRoot;
    Hash stateRoot;
    Hash receiptsRoot;
    Address miner;
    BigInt difficulty;
    BigInt totalDifficulty;
    bytes extraData;
    ulong size;
    BigInt gasLimit;
    BigInt gasUsed;
    BigInt timestamp;
    bytes[] transactions;
    Hash[] uncles;
}

struct TransactionReceipt
{
    Hash transactionHash; // DATA, 32 Bytes - hash of the transaction.
    ulong transactionIndex; // QUANTITY - integer of the transactions index position in the block.
    Hash blockHash; // DATA, 32 Bytes - hash of the block where this transaction was in.
    ulong blockNumber; // QUANTITY - block number where this transaction was in.
    Address from; // DATA, 20 Bytes - address of the sender.
    Nullable!Address to; // DATA, 20 Bytes - address of the receiver. null when its a contract creation transaction.
    BigInt cumulativeGasUsed; // QUANTITY - The total amount of gas used when this transaction was executed in the block.
    BigInt gasUsed; // QUANTITY - The amount of gas used by this specific transaction alone.
    Nullable!Address contractAddress; // DATA, 20 Bytes - The contract address created, if the transaction was a contract creation, otherwise null.
    Log[] logs; // Array - Array of log objects, which this transaction generated.
    bytes logsBloom; // DATA, 256 Bytes - Bloom filter for light clients to quickly retrieve related logs.a
    ulong type; // QUANTITY - integer of the transaction type, 0x0 for legacy transactions, 0x1 for access list types, 0x2 for dynamic fees.
}

struct TransactionInfo
{
    Nullable!Hash blockHash;
    Nullable!ulong blockNumber;
    Address from;
    BigInt gas;
    BigInt gasPrice;
    bytes input;
    ulong nonce;
    Nullable!Address to;
    Nullable!ulong transactionIndex;
    BigInt value;

    ulong v;
    Hash r;
    Hash s;
}

struct Log
{
    bool removed;
    Address address; //  DATA, 20 Bytes - address from which this log originated.
    bytes data; //  DATA - contains one or more 32 Bytes non-indexed arguments of the log.
    Hash[] topics; //  Array of DATA - Array of 0 to 4 32 Bytes DATA of indexed log arguments. (In solidity; //  The first topic is the hash of the signature of the event (e.g. Deposit(address,bytes32,uint256)), except you declared the event with the anonymous specifier.)
}

struct StorageProof
{
    bytes key; // Storage key.
    bytes value; // Value that the key holds
    bytes[] proof; // proof for the pair
}

// https://github.com/ethereum/execution-apis/blob/v1.0.0-beta.4/src/schemas/state.yaml#L1
struct ProofResponse
{
    Address address;
    bytes[] accountProof;
    BigInt balance;
    Hash codeHash;
    ulong nonce;
    Hash storageHash;
    StorageProof[] storageProof;
}

alias AccessList = AccessListItem[];

struct AccessListItem
{
    Address addess;
    BigInt[] storageKeys;
}
