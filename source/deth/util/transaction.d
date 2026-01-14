module deth.util.transaction;

import core.sync;
import std.array : replace;
import std.bigint : BigInt;
import std.conv : to;
import std.digest : toHexString;
import std.exception;
import std.format;
import std.json : JSONValue;
import std.sumtype;
import std.typecons : Nullable;

import deth.util.types;
import deth.rpcconnector : RPCConnector;

import rlp.encode : encode, encodeLength;
import rlp.header;
import secp256k1 : Signature;

// https://eips.ethereum.org/EIPS/eip-2718
enum TransactionType : ubyte
{
    LEGACY = 0,
    EIP1559 = 2
}

alias Transaction = SumType!(
    EIP1559Transaction,
    LegacyTransaction
);

JSONValue toJSON(Transaction tx) pure @safe
{
    return tx.match!(
        (EIP1559Transaction eip1559Tx) => eip1559Tx.toJSON,
        (LegacyTransaction legacyTx) => legacyTx.toJSON
    );
}

struct EIP1559Transaction
{
    Nullable!Address from;
    Nullable!ulong chainid;
    Nullable!ulong nonce;
    Nullable!BigInt maxPriorityFeePerGas;
    Nullable!BigInt maxFeePerGas;
    Nullable!BigInt gas;
    Nullable!Address to;
    Nullable!BigInt value;
    Nullable!bytes data = [];
    Nullable!AccessList accessList;

    TransactionType type() pure const nothrow @safe
    {
        return TransactionType.EIP1559;
    }

    JSONValue toJSON() pure const @safe
    {
        string[string] result;
        static foreach (field; [
                "from", "to", "gas", "value", "data",
            ])
        {
            mixin(q{if (!%s.isNull)
                result[`%s`] = %s.get.convTo!string.ox;}.format(field, field, field));
        }
        static foreach (field; [
                "chainid", "maxFeePerGas", "maxPriorityFeePerGas", "accessList",
            ])
        {
            mixin(q{if (!%s.isNull)
                result[`%s`] = %s.get.to!string;}.format(field, field, field));
        }
        if (!nonce.isNull)
            result["nonce"] = nonce.get.to!string(16).ox;
        return result.JSONValue;
    }

    bytes serializeToRLP() pure const @safe
    {
        bytes rlpTx = [type];
        Header header = { isList: true, payloadLen: 0 };
        header.payloadLen =
            chainid.encodeLength() +
            nonce.encodeLength() +
            maxPriorityFeePerGas.encodeLength() +
            maxFeePerGas.encodeLength() +
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            accessList.encodeLength();
        header.encodeHeader(rlpTx);
        chainid.encode(rlpTx);
        nonce.encode(rlpTx);
        maxPriorityFeePerGas.encode(rlpTx);
        maxFeePerGas.encode(rlpTx);
        gas.encode(rlpTx);
        to.encode(rlpTx);
        value.encode(rlpTx);
        data.encode(rlpTx);
        accessList.encode(rlpTx);
        
        return rlpTx;
    }

    bytes serializeToSignedRLP(Signature signature) pure const @safe
    {
        bytes signedTx = [type];
        Header signedTxHeader = { isList: true, payloadLen: 0 };
        signedTxHeader.payloadLen =
            chainid.encodeLength() +
            nonce.encodeLength() +
            maxPriorityFeePerGas.encodeLength() +
            maxFeePerGas.encodeLength() +
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            accessList.encodeLength() +
            (cast(bool) signature.recid).encodeLength() +
            signature.r.encodeLength() +
            signature.s.encodeLength();
        signedTxHeader.encodeHeader(signedTx);
        chainid.encode(signedTx);
        nonce.encode(signedTx);
        maxPriorityFeePerGas.encode(signedTx);
        maxFeePerGas.encode(signedTx);
        gas.encode(signedTx);
        to.encode(signedTx);
        value.encode(signedTx);
        data.encode(signedTx);
        accessList.encode(signedTx);
        (cast(bool) signature.recid).encode(signedTx);
        signature.r.encode(signedTx);
        signature.s.encode(signedTx);

        return signedTx;
    }
}

@("eip-1559 encoding test")
unittest
{
   EIP1559Transaction tx = {
       chainid: 1,
       nonce: 0,
       maxPriorityFeePerGas: "2000000000".BigInt,
       maxFeePerGas: "3000000000".BigInt,
       gas: "78009".BigInt,
       to: "0x6b175474e89094c44da98b954eedeac495271d0f".convTo!Address,
       value: "0".BigInt,
       data: "0xa9059cbb0000000000000000000000005322b34c88ed0691971bf52a7047448f0f4efc840000000000000000000000000000000000000000000000001bc16d674ec80000".convTo!bytes,
   };
   auto rlpTx = tx.serializeToRLP();
   auto expected = "0x02f86D0180847735940084b2d05e00830130b9946b175474e89094c44da98b954eedeac495271d0f80b844a9059cbb0000000000000000000000005322b34c88ed0691971bf52a7047448f0f4efc840000000000000000000000000000000000000000000000001bc16d674ec80000c0".convTo!bytes;
   assert(rlpTx == expected);
}

struct LegacyTransaction
{
    Nullable!Address from;
    Nullable!Address to;
    Nullable!BigInt gas;
    Nullable!BigInt gasPrice;
    Nullable!BigInt value;
    Nullable!bytes data = [];
    Nullable!ulong nonce;
    Nullable!ulong chainid;

    invariant
    {
        assert(gas.isNull || gas.get >= 0);
        assert(gasPrice.isNull || gasPrice.get >= 0);
        assert(value.isNull || value.get >= 0);
    }

    JSONValue toJSON() pure const @safe
    {
        string[string] result;
        static foreach (field; [
                "from", "to", "gas", "gasPrice", "value", "data",
            ])
        {
            mixin(q{if (!%s.isNull)
                    result["%s"] = %s.get.convTo!string.ox;}.format(field, field, field));
        }
        if (!nonce.isNull)
            result["nonce"] = nonce.get.to!string(16).ox;
        return result.JSONValue;
    }

    bytes serializeToRLP() pure const @safe
    {
        bytes rlpTx;
        Header header = { isList: true, payloadLen: 0 };
        header.payloadLen =
            nonce.encodeLength() +
            gasPrice.encodeLength()+
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength();
        if (!chainid.isNull)
        {
            header.payloadLen += chainid.encodeLength();
            header.payloadLen += 2;
        }
        header.encodeHeader(rlpTx);
        nonce.encode(rlpTx);
        gasPrice.encode(rlpTx);
        gas.encode(rlpTx);
        to.encode(rlpTx);
        value.encode(rlpTx);
        data.encode(rlpTx);
        if (!chainid.isNull)
        {
            chainid.encode(rlpTx);
            rlpTx ~= [0x80, 0x80];
        }

        return rlpTx;
    }

    bytes serializeToSignedRLP(Signature signature) pure const @safe
    {
        bytes signedTx;
        Header signedTxHeader = { isList: true, payloadLen: 0 };
        ulong v = chainid.isNull
            ? 27 + signature.recid
            : signature.recid + chainid.get * 2 + 35 /* eip 155 signing */ ;
        signedTxHeader.payloadLen =
            nonce.encodeLength() +
            gasPrice.encodeLength()+
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            v.encodeLength() +
            signature.r.encodeLength() +
            signature.s.encodeLength();
        signedTxHeader.encodeHeader(signedTx);
        nonce.encode(signedTx);
        gasPrice.encode(signedTx);
        gas.encode(signedTx);
        to.encode(signedTx);
        value.encode(signedTx);
        data.encode(signedTx);
        v.encode(signedTx);
        signature.r.encode(signedTx);
        signature.s.encode(signedTx);

        return signedTx;
    }
}

static foreach (f, t; [
        "From": "Address",
        "To": "Address",
        "Gas": "BigInt",
        "GasPrice": "BigInt",
        "Value": "BigInt",
        "Data": "bytes",
        "Nonce": "ulong",
        "ChainId": "ulong",
        "MaxPriorityFeePerGas": "BigInt",
        "MaxFeePerGas": "BigInt",
        "AccessList": "bytes",
    ])
{
    mixin NamedParameter!(f, t);
}

alias SendableTransaction = SumType!(
    SendableEIP1559Transaction,
    SendableLegacyTransaction
);

Hash send(ARGS...)(SendableTransaction tx, ARGS params) @safe
{
    return tx.match!(
        (SendableEIP1559Transaction eip1559Tx) => eip1559Tx.send(params),
        (SendableLegacyTransaction legacyTx) => legacyTx.send(params)
    );
}

struct SendableEIP1559Transaction
{
    EIP1559Transaction tx;
    private RPCConnector conn;

    Hash send(ARGS...)(ARGS params) @safe
    {
        static foreach (i; 0 .. ARGS.length)
        {
            static if (is(ARGS[i] == From))
                tx.from = params[i].value;
            else static if (is(ARGS[i] == To))
                tx.to = params[i].value;
            else static if (is(ARGS[i] == Value))
                tx.value = params[i].value;
            else static if (is(ARGS[i] == Gas))
                tx.gas = params[i].value;
            else static if (is(ARGS[i] == Nonce))
                tx.nonce = params[i].value;
            else static if (is(ARGS[i] == Data))
                tx.data = params[i].value;
            else static if (is(ARGS[i] == ChainId))
                tx.chainid = params[i].value;
            else static if (is(ARGS[i] == MaxPriorityFeePerGas))
                tx.maxPriorityFeePerGas = params[i].value;
            else static if (is(ARGS[i] == MaxFeePerGas))
                tx.maxFeePerGas = params[i].value;
            else static if (is(ARGS[i] == AccessList))
                tx.accessList = params[i].value;
            else
                static assert(0, "Not supported param " ~ ARGS[i].stringof);
        }

        if (tx.from.isNull)
        {
            auto accList = conn.accounts ~ conn.remoteAccounts;
            enforce(accList.length > 0, " No accounts are unlocked");
            tx.from = accList[0];
        }
        if (tx.gas.isNull)
        {
            tx.gas = conn.estimateGas(tx) * conn.gasEstimatePercentage / 100;
        }
        synchronized
        {
            if (tx.nonce.isNull)
            {
                tx.nonce = conn.getTransactionCount(tx.from.get);
            }
            if (conn.isUnlocked(tx.from.get))
            {
                return conn.sendRawTransaction(tx);
            }
            else if (conn.isUnlockedRemote(tx.from.get))
            {
                return conn.sendTransaction(tx);
            }
        }
        assert(0);
    }
}

struct SendableLegacyTransaction
{
    LegacyTransaction tx;
    private RPCConnector conn;

    Hash send(ARGS...)(ARGS params) @safe
    {
        static foreach (i; 0 .. ARGS.length)
        {
            static if (is(ARGS[i] == From))
                tx.from = params[i].value;
            else static if (is(ARGS[i] == To))
                tx.to = params[i].value;
            else static if (is(ARGS[i] == Value))
                tx.value = params[i].value;
            else static if (is(ARGS[i] == Gas))
                tx.gas = params[i].value;
            else static if (is(ARGS[i] == GasPrice))
                tx.gasPrice = params[i].value;
            else static if (is(ARGS[i] == Nonce))
                tx.nonce = params[i].value;
            else static if (is(ARGS[i] == Data))
                tx.data = params[i].value;
            else
                static assert(0, "Not supported param " ~ ARGS[i].stringof);
        }

        if (tx.from.isNull)
        {
            auto accList = conn.accounts ~ conn.remoteAccounts;
            enforce(accList.length > 0, " No accounts are unlocked");
            tx.from = accList[0];
        }
        if (tx.gas.isNull)
        {
            tx.gas = conn.estimateGas(tx) * conn.gasEstimatePercentage / 100;
        }
        if (tx.gasPrice.isNull)
        {
            tx.gasPrice = conn.gasPrice;
        }
        synchronized
        {
            if (tx.nonce.isNull)
            {
                tx.nonce = conn.getTransactionCount(tx.from.get);
            }
            if (conn.isUnlocked(tx.from.get))
            {
                return conn.sendRawTransaction(tx);
            }
            else if (conn.isUnlockedRemote(tx.from.get))
            {
                return conn.sendTransaction(tx);
            }
        }
        assert(0);
    }
}

mixin template NamedParameter(string fieldName, string type)
{
    mixin(q{
            struct %s
            {
            %s value;
            }
            }.format(fieldName, type));
}
