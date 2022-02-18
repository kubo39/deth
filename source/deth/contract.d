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
import deth.util.transaction : SendableTransaction;
import keccak : keccak_256;

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
    static auto deployTx(ARGS...)(RPCConnector conn, ARGS argv)
    {
        Transaction tx;
        assert(deployedBytecode.length, "deployedBytecode should be set");
        tx.data = deployedBytecode ~ encode(argv);
        return SendableTransaction(tx, conn);
    }

    override string toString() const
    {
        return " Contract on 0x" ~ address.convTo!string;
    }

    auto callMethod(Selector selector, ARGS...)(Address from, BigInt value, ARGS argv)
    {
        Transaction tx;
        tx.data = selector[];
        tx.value = value;
        tx.from = from;
        static if (ARGS.length != 0)
            tx.data = selector[] ~ encode(argv);
        tx.to = this.address;
        return conn.call(tx, BlockNumber.LATEST);
    }

    auto sendMethod(Selector selector, ARGS...)(ARGS argv)
    {
        Transaction tx;
        tx.data = selector[];
        tx.to = this.address;
        static if (ARGS.length != 0)
            tx.data = selector[] ~ encode(argv);
        tx.data.get.convTo!string.writeln;
        return SendableTransaction(tx, conn);
    }
}

private string allFunctions(ContractABI abi)
{
    string code = "";

    code ~= q{
        auto %s
        {
            auto txHash = %s.send(argv);
            auto addr = conn.waitForTransactionReceipt(txHash).contractAddress.get;
            return new Contract!abi(conn, addr);
        }
    }.format(abi.deploySignature, abi.deployArgs);

    foreach (func; abi.functions)
    {
        if (func.constant)
        {
            auto returns = func.outputType.toDType;
            auto dSignature = func.dSignature([
                "Address from = Address.init", "BigInt value = 0.BigInt"
            ]);
            auto dargs = func.dargs("from", "value");
            code ~= q{
                %s %s
                {
                    return callMethod!(%s)%s.decode!%s;
                }
            }.format(returns, dSignature, func.selector, dargs, returns);
        }
        else
        {
            code ~= q{
                SendableTransaction %s
                {
                    return sendMethod!(%s)%s;
                }
            }.format(func.dSignature, func.selector, func.dargs);
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

    string deploySignature() const @property
    {
        string[] args = ["RPCConnector conn"];
        foreach (i, t; constructorInputs)
        {
            args ~= t.toDType ~ " v" ~ i.to!string;
        }
        args ~= ["ARGS argv"];
        return "deploy(ARGS...)".getSignature(args);
    }

    string deployArgs() const @property
    {
        string[] args = ["conn"];
        foreach (i; 0 .. constructorInputs.length)
        {
            args ~= " v" ~ i.to!string;
        }
        return "deployTx".getSignature(args);
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
        fn.mutability = cast(Mutability) item[`stateMutability`].str;
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

    string toString() const
    {
        return contractName;
    }
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

    string name;
    Selector selector;
    string outputType;
    string[] inputTypes;
    Mutability mutability;
    bool payable;
    bool constant;
    mixin Signature;

    string dSignature(string[] additional...)
    {
        string[] args = [];
        foreach (i, type; inputTypes)
        {
            args ~= type.toDType ~ " v" ~ i.to!string;
        }
        args ~= additional;
        return name.getSignature(args);
    }

    private string dargs(string[] additional...)
    {
        string[] args = [];
        foreach (i, _; inputTypes)
        {
            args ~= " v" ~ i.to!string;
        }
        args = additional ~ args;
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

enum Mutability
{
    PURE = "pure",
    VIEW = "view",
    PAYABLE = "payable",
    NONPAYABLE = "nonpayable",
}
