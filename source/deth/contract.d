module deth.contract;

import std : toHexString, to;
import structjson;
import std.bigint : BigInt;
import std.stdio;
import std.array : replace, join;
import std.string : indexOf, format;
import std.algorithm : canFind;
import deth.util.abi : encode, decode;
import deth.util.types;
import deth.rpcconnector;

import keccak : keccak_256;

static immutable INTEGRAL = ["address", "uint256", "int256", "int32"];

alias Selector = ubyte[4];

class Contract(ContractABI abi)
{
    Address address;
    private RPCConnector conn;

    static bytes deployedBytecode;

    this(RPCConnector conn, Address addr)
    {
        this.conn = conn;
        this.address = addr;
    }

    debug pragma(msg, allFunctions(abi));
    mixin(allFunctions(abi));

    // Sends traansaction for deploy contract
    static auto deploy(ARGS...)(RPCConnector conn, ARGS argv)
    {
        string from = null;
        Transaction tr;
        assert(deployedBytecode.length, "deployedBytecode should be set");
        tr.from = (from is null ? conn.eth_accounts[0] : from).convTo!Address;
        tr.data = deployedBytecode ~ encode(argv);
        tr.gas = 6_721_975.BigInt;
        tr.value = 0.BigInt;
        auto trHash = conn.sendTransaction(tr);
        auto address = conn.getTransactionReceipt(trHash).get.contractAddress.get;
        return new Contract!abi(conn, address);
    }

    override string toString() const
    {
        return " Contract on 0x" ~ address.convTo!string;
    }

    auto callMethod(Selector selector, ARGS...)(ARGS argv)
    {
        Transaction tr;
        tr.data = selector[] ~ encode(argv);
        tr.from = conn.eth_accounts[0][2 .. $].convTo!Address;
        tr.to = this.address;
        return conn.call(tr, BlockNumber.LATEST);
    }
}

private string allFunctions(ContractABI abi)
{
    string code = "";
    foreach (func; abi.functions)
    {
        auto returns = func.outputType.toDType;
        if (returns == "void")
        {
            code ~= q{
                %s %s
                {
                    callMethod!(%s)%s;
                }
            }.format(returns, func.dSignature, func.selector, func.dargs);
        }
        else
        {
            code ~= q{
                %s %s
                {
                    return callMethod!(%s)%s.decode!%s;
                }
            }.format(returns, func.dSignature, func.selector, func.dargs, returns);
        }
    }
    return code;
}

struct ContractABI
{
    string contractName;
    string[] constructorInputs;
    ContractFunction[] functions;
    ContractEvent[] events;

    this(JSONValue abi, string name = "Noname")
    {
        contractName = name;
        fromJSON(abi);
    }

    private void fromJSON(JSONValue abi)
    {
        assert(abi.type == JSONType.array);
        JSONValue[] items = abi.array;
        foreach (i; 0 .. items.length)
        {
            string type = items[i][`type`].str;
            if (`function` == type)
                functionFromJson(items[i]);
            if (`constructor` == type)
                constructorInputs = items[i][`inputs`].parseInputs;
            if (`event` == type)
                events = [];
        }
    }

    private void functionFromJson(JSONValue item)
    {
        ContractFunction fn;

        if (`outputs` in item && !item[`outputs`].isNull)
        {
            fn.outputType = parseOutput(item[`outputs`]);
        }
        fn.mutability = item[`stateMutability`].str;
        if (fn.mutability == Mutability.PAYABLE)
        {
            fn.payable = true;
        }
        else if (fn.mutability == Mutability.VIEW || fn.mutability == Mutability.PURE)
        {
            fn.constant = true;
        }
        fn.inputTypes = item[`inputs`].parseInputs;
        fn.name = item[`name`].str;
        keccak_256(fn.selector.ptr, fn.selector.length,
                cast(ubyte*) fn.signature.ptr, fn.signature.length);
        functions ~= fn;
    }

    private void eventFromJson(JSONValue item)
    {
        ContractEvent ev;
        ev.inputTypes = item[`inputs`].parseInputs;
        ev.indexedInputTypes = item[`inputs`].parseInputs!(a => a[`indexed`].boolean);
        ev.name = item[`name`].str;
        keccak_256(ev.sigHash.ptr, ev.sigHash.length,
                cast(ubyte*) ev.signature.ptr, ev.signature.length);
    }

    // string toString() const
    // {
    //     return contractName;
    // }
}

private mixin template Signature()
{
    @property auto signature()
    {
        return getSignature(name, inputTypes);
    }
}

private string getSignature(string name, string[] args)
{
    return name ~ `(` ~ args.join(',') ~ `)`;
}

struct ContractFunction
{

    enum Mutability
    {
        PURE = "pure",
        VIEW = "view",
        PAYABLE = "payable",
        NONPAYABLE = "nonpayable",
    }

    string name;
    Selector selector;
    string outputType;
    string[] inputTypes;
    Mutability mutability;
    bool payable;
    bool constant;
    mixin Signature;

    @property string dSignature()
    {
        string[] args = [];
        foreach (i, type; inputTypes)
        {
            args ~= type.toDType ~ " v" ~ i.to!string;
        }
        return name.getSignature(args);
    }

    private @property string dargs()
    {
        string[] args = [];
        foreach (i, _; inputTypes)
        {
            args ~= " v" ~ i.to!string;
        }
        return "".getSignature(args);
    }
}

struct ContractEvent
{
    string name;
    Hash sigHash;
    string[] inputTypes;
    string[] indexedInputTypes;
    mixin Signature;
}

private string parseOutput(JSONValue outputs)
{
    string[] outputTypes = [];
    JSONValue[] outputsObjs = outputs.array;
    foreach (JSONValue i; outputsObjs)
    {

        auto outputType = i[`type`].str;
        if (outputType.canFind("tuple"))
            outputType = outputType.replace("tuple", i[`components`].parseTuple);
        outputTypes ~= outputType;
    }
    if (outputTypes.length == 0)
        return `void`;
    if (outputTypes.length == 1)
        return outputTypes[0];
    return `tuple(` ~ outputTypes.join(',') ~ `)`;

}

private string[] parseInputs(alias filter = null)(JSONValue inputs)
{
    import std.traits : isCallable;

    string[] inputTypes = [];
    assert(inputs.type == JSONType.array);
    foreach (JSONValue input; inputs.array)
    {
        auto inputType = input[`type`].str;
        if (inputType.canFind("tuple"))
            inputType = inputType.replace("tuple", input[`components`].parseTuple);
        static if (isCallable!filter)
        {
            if (input.filter)
                continue;
        }
        inputTypes ~= inputType;

    }
    return inputTypes;
}

private string parseTuple(JSONValue components)
{
    string[] typesToJoin = [];
    foreach (type; components.array)
    {
        auto typeName = type[`type`].str;
        if (typeName.canFind("tuple"))
        {
            typesToJoin ~= typeName.replace(`tuple`, type[`components`].parseTuple);
        }
        else
            typesToJoin ~= typeName;
    }
    return `tuple(` ~ typesToJoin.join(',') ~ `)`;
}

unittest
{
}

private string toDType(string SolType)
{
    string DType = SolType.replace("tuple", "tuple!");
    DType = DType.replace("bytes", "ubyte[]");
    DType = DType.replace("address", "Address");
    /// size circle
    foreach (size; 1 .. 33)
    {
        auto bits = to!string(size * 8);
        auto size_s = size.to!string;
        DType = DType.replace("uint" ~ bits, "BigInt");
        DType = DType.replace("int" ~ bits, "BigInt");
        DType = DType.replace("bytes" ~ size_s, "ubyte[" ~ size_s ~ "]");
    }
    return DType;
}

unittest
{
    assert("int256".toDType == "BigInt", "int256".toDType);
    assert("uint256".toDType == "BigInt", "uint256".toDType);
}
