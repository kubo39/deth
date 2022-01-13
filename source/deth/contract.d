module deth.contract;

import std : toHexString, to;
import std.json;
import std.bigint : BigInt;
import std.stdio;
import std.array : replace, join;
import std.string : indexOf;
import std.algorithm : canFind;
import deth.util.abi : encode;
import deth.util.types;
import deth.rpcconnector;

import keccak : keccak_256;

enum INTEGRAL = ["address", "uint256", "int256", "int32"];

class Contract(string buildPath, string bin)
{
    enum build = import(buildPath).parseJSON;
    enum abi = build;
    Address address;
    private RPCConnector conn;

    static immutable string deployedBytecode = bin;

    this(RPCConnector conn)
    {
        this.conn = conn;
        this.address = null;
    }

    debug pragma(msg, allFunctions(abi));
    mixin(allFunctions(abi));

    // Send traansaction for deploy contract
    void deploy(ARGS...)(ARGS argv)
    {
        string from = null;
        Transaction tr;
        tr.from = (from is null ? conn.eth_accounts[0] : from)[2 .. $].convTo!Address;
        tr.data = deployedBytecode[2 .. $].hexToBytes ~ encode(argv);
        tr.gas = 6_721_975.BigInt;
        auto trHash = conn.eth_sendTransaction(tr.toJSON)[2 .. $].convTo!Hash;
        address = conn.getTransactionReceipt(trHash).contractAddress.get;
    }

    override string toString()
    {
        return " Contract on 0x" ~ address.convTo!string;
    }

    auto callMethod(string signiture, ARGS...)(ARGS argv)
    {
        ubyte[4] hashOfSign;
        keccak_256(hashOfSign.ptr, hashOfSign.length,
                cast(ubyte*) signiture.ptr, signiture.length);
        auto inputs = argv.encode;

        Transaction tr;
        tr.data = hashOfSign[] ~ inputs;
        tr.from = conn.eth_accounts[0][2 .. $].convTo!Address;
        tr.to = this.address;
        return conn.call(tr, BlockNumber.LATEST);
    }
}

string parseFunction(JSONValue abi)
{
    return (q{
            void $funcName ( $inputs ) {
            $body
            }
            }.replace("$funcName", abi["name"].str).replace("$inputs",
            abi["inputs"].getInputs).replace("$body", q{callMethod!"$signature"($inputsValue);}).replace("$signature",
            abi.getSigniture).replace("$inputsValue", abi["inputs"].getInputs(false)));
}

string allFunctions(JSONValue abi)
{
    string retVal = "";
    foreach (JSONValue func; abi.array)
    {
        if (func["type"].str == "function")
        {
            retVal ~= func.parseFunction ~ "\n";
        }
    }
    return retVal;
}

string getInputs(JSONValue params, bool typed = true)
{
    string[] inputs = [];
    foreach (param; params.array)
    {
        try
        {
            if (param["type"].str.isIntegral)
            {

                inputs ~= (typed ? "BigInt " : "") ~ param["name"].str;
            }
            else if ("bool" == param["type"].str)
            {
                inputs ~= (typed ? "bool " : "") ~ param["name"].str;
            }
        }
        catch (Exception e)
        {
            continue;
        }

    }
    return inputs.join(", ");
}

string getSigniture(JSONValue abi)
{
    JSONValue params = abi["inputs"];
    string[] types = [];
    foreach (param; params.array)
    {
        types ~= param["type"].str;
    }
    return abi["name"].str ~ "(" ~ types.join(",") ~ ")";
}

bool isIntegral(string typeName)
{
    return INTEGRAL.canFind(typeName);
}

bool isDynamicArray(string typeName)
{
    return typeName[$ - 2 .. $] == "[]";
}
