module deth.util.transaction;

import std : Nullable;
import std.json : JSONValue;
import std.bigint : BigInt;
import std.digest : toHexString;
import std.array : replace;
import std.format;
import std.conv : to;

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

struct SendableTransaction
{
    Transaction tx;
    private RPCConnector conn;

    static foreach (f, t; [
            "from": "Address",
            "to": "Address",
            "gas": "BigInt",
            "gasPrice": "BigInt",
            "value": "BigInt",
            "data": "bytes",
            "nonce": "ulong",
        ])
    {
        mixin(createSetter(t, f, ".tx"));
    }

    Hash send()
    {
        if (tx.from.isNull)
        {
            assert(0, "Not implemeted");
        }
        if (conn.isUnlocked(tx.from.get))
        {
            return conn.sendRawTransaction(tx);
        }
        else if (conn.isUnlockedRemote(tx.from.get))
        {
            return conn.sendTransaction(tx);
        }
        assert(0, "бачок потік");
    }
}

private string createSetter(string fieldType, string fieldName, string includedField = "")
{
    return q{
        @property ref auto %s(%s value){
            this%s.%s = value;
            return this;
        }
    }.format(fieldName, fieldType, includedField, fieldName);
}
