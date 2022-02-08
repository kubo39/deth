module deth.util.types;

import std.algorithm : reverse;
import std.conv : to;
import std : toHexString;
import std.json : JSONValue;
import std : Nullable, BigInt;

public import deth.util.transaction : Transaction;

alias Address = ubyte[20];
alias Hash = ubyte[32];
alias bytes = ubyte[];

bytes hexToBytes(string s)
{
    import std : chunks, map, array, startsWith;
    import std.range : padLeft;

    if (s.startsWith(`0x`))
        s = s[2 .. $];

    return s.padLeft('0', s.length + s.length % 2).chunks(2).map!q{a.parse!ubyte(16)}.array;
}

unittest
{
    assert("0x123".hexToBytes == [0x1, 0x23]);
}

To convTo(To, _From)(const _From f)
{
    import std.traits : Unconst;

    alias From = Unconst!_From;
    static if (is(From == bytes))
    {
        static if (is(To == string))
        {
            return f.toHexString;
        }
    }
    static if (is(From == Address))
    {
        static if (is(To == string))
        {
            return (cast(bytes) f).toHexString.to!string;
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
            return (cast(bytes) f).toHexString.to!string;
        }
        static if (is(To == bytes))
        {
            return f[];
        }
    }
    // BigInt Part
    import std.bigint : BigInt, toHex;

    static if (is(From == BigInt))
    {
        static if (is(To == bytes))
        {
            import std : chunks, replace, map, array;
            import std.range : padLeft;

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
            Address[] v = cast(Address[]) f.hexToBytes().padLeft(0, 20);
            return v[0];
        }
        static if (is(To == Hash))
        {
            Hash[] v = cast(Hash[]) f.hexToBytes().padLeft(0, 32);
            return v[0];
        }
        static if (is(To == bytes))
        {
            return f.hexToBytes;
        }
    }
    static if (is(From == JSONValue))
    {
        static if (is(To == TransactionReceipt))
        {
            TransactionReceipt tx;
            tx.transactionIndex = f[`transactionIndex`].str[2 .. $].to!ulong(16);
            tx.from = f[`from`].str[2 .. $].convTo!Address;
            tx.blockHash = f[`blockHash`].str[2 .. $].convTo!Hash;
            tx.blockNumber = f[`blockNumber`].str[2 .. $].to!ulong(16);
            if (!f[`to`].isNull)
                tx.to = f[`to`].str[2 .. $].convTo!Address;
            tx.cumulativeGasUsed = f[`cumulativeGasUsed`].str.BigInt;
            tx.gasUsed = f[`gasUsed`].str.BigInt;
            if (!f[`contractAddress`].isNull)
                tx.to = f[`contractAddress`].str[2 .. $].convTo!Address;
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
            return tx;
        }
        static if (is(To == TransactionInfo))
        {
            TransactionInfo info;
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
            return info;
        }
    }
}

unittest
{
    import std;

    ///looks like big endian coding
    bytes becodedNum = [15, 255, 255, 255, 255, 170];
    assert(`0xfffffffffaa`.BigInt.convTo!bytes == becodedNum);

    Address addr;
    assert(addr.convTo!string == join(20.iota.array.map!q{"00"}));

    enum T
    {
        A,
        B
    }

    assert(!__traits(compiles, addr.convTo!T), `shouldn't compile with undefined conv pair`);
}

pure auto ox(T)(T t)
{
    return `0x` ~ t[];
}

auto padLeft(bytes data, ubyte b, ulong count)
{
    if (count > data.length)
    {
        auto pad = new ubyte[count - data.length];
        pad[] = b;
        return pad ~ data;
    }
    else
        return data;
}

auto padRight(bytes data, ubyte b, ulong count)
{
    if (count > data.length)
    {
        auto pad = new ubyte[count - data.length];
        pad[] = b;
        return data ~ pad;
    }
    else
        return data;
}

unittest
{
    import std;

    assert("0x123" == `123`.ox);
    char[4] t;
    t[] = 'a';
    assert(t.ox == "0xaaaa");
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
