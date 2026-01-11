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

import rlp.encode;

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
    Nullable!(bytes[]) accessList;

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
