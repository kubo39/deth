module deth.util.transaction;

import std : Nullable;
import std.json : JSONValue;
import std.bigint : BigInt;
import std.digest : toHexString;
import std.array : replace;
import std.format;
import std.conv : to;
import std.stdio;
import std.exception;

import deth.util.types;
import deth.util.rlp : rlpEncode, cutBytes;
import deth.rpcconnector : RPCConnector;

struct Transaction
{
    Nullable!Address from;
    Nullable!Address to;
    Nullable!BigInt gas;
    Nullable!BigInt gasPrice;
    Nullable!BigInt value;
    Nullable!bytes data = [];
    Nullable!ulong nonce;

    invariant
    {
        assert(gas.isNull || gas.get >= 0);
        assert(gasPrice.isNull || gasPrice.get >= 0);
        assert(value.isNull || value.get >= 0);
    }

    JSONValue toJSON()
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

    bytes[] serialize()
    {
        bytes[] encoded = [];
        if (nonce.isNull)
            encoded ~= [[]];
        else
            encoded ~= cutBytes(cast(bytes)[nonce.get]);

        static immutable code = q{
            if(field.isNull)
                encoded ~= [[]];
            else
                encoded ~= field.get.convTo!bytes;
        };
        static foreach (field; ["gasPrice", "gas", "to", "value"])
        {
            mixin(code.replace("field", field));
        }
        encoded ~= data.get;
        return encoded;
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
    ])
{
    mixin NamedParameter!(f, t);
}

struct SendableTransaction
{
    Transaction tx;
    private RPCConnector conn;

    Hash send(ARGS...)(ARGS params)
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
        if (tx.nonce.isNull)
        {
            tx.nonce = conn.getTransactionCount(tx.from.get);
        }
        if (tx.gas.isNull)
        {
            tx.from.writeln;
            tx.gas = conn.estimateGas(tx) * conn.gasEstimatePercentage / 100;
        }
        if (tx.gasPrice.isNull)
        {
            tx.gasPrice = conn.gasPrice;
        }
        if (conn.isUnlocked(tx.from.get))
        {
            return conn.sendRawTransaction(tx);
        }
        else if (conn.isUnlockedRemote(tx.from.get))
        {
            return conn.sendTransaction(tx);
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
