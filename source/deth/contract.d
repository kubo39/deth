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
import keccak : keccak256;

import std.experimental.logger;

alias Selector = ubyte[4];

/// Alias for Contract without ABI
alias NonABIContract = Contract!();

///     
/// Params: 
///   abi = abi of contract  
class Contract(ContractABI abi = ContractABI.init)
{
    Address address;
    private RPCConnector conn;
    static bytes bytecode;
    static string _bytecode;
    static size_t[string] spaceholders;

    this(RPCConnector conn, Address addr)
    {
        this.conn = conn;
        this.address = addr;
    }

    version (unittest)
    {
        debug pragma(msg, allFunctions(abi));
    }
    mixin(allFunctions(abi));

    // Sends traansaction for deploy contract
    static auto deployTx(ARGS...)(RPCConnector conn, ARGS argv)
    {
        Transaction tx;
        assert(bytecode.length, "bytecode should be set");
        bytes argvEncoded = [];
        static if (argv.length > 0)
        {
            argvEncoded = encode(argv);
        }
        tx.data = bytecode ~ argvEncoded;
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
        return SendableTransaction(tx, conn);
    }

    auto callMethodS(string signature, Result = void, ARGS...)(ARGS argv)
    {
        static immutable selector = keccak256(cast(ubyte[]) signature)[0 .. 4];
        auto data = callMethod!selector(Address.init, 0.BigInt, argv);
        logCall(signature);
        static if (is(Result == void))
            return data;
        else
            return data.decode!Result;
    }

    auto sendMethodS(string signature, Result = void, ARGS...)(ARGS argv)
    {
        static immutable selector = keccak256(cast(ubyte[]) signature)[0 .. 4];
        logCall(signature);
        return sendMethod!selector(argv);
    }

    private void logCall(string selector)
    {
        tracef("Calling %s %s(0x%s)", selector, abi.contractName, this.address.convTo!string);
    }

    static void link(string contractName, Address addr)
    {
        if (spaceholders.keys.canFind(contractName))
            return;
        auto offset = spaceholders[contractName];
        auto spaceholder = _bytecode[offset .. offset + 40];
        _bytecode = _bytecode.replace(spaceholder, addr.convTo!string);
        spaceholders.remove(contractName);
        if(spaceholders.keys.length == 0){
            bytecode = _bytecode.convTo!bytes;
        }
    }
}

private string allFunctions(ContractABI abi)
{
    string code = "";
    if (abi == ContractABI.init)
        return code;
    code ~= q{
        static auto %s
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
            logCall("%s");
            return callMethod!(%s)%s.decode!%s;
        }}.format(returns, dSignature, func.signature, func.selector, dargs, returns);
        }
        else
        {
            code ~= q{
        SendableTransaction %s
        {
            logCall("%s");
            return sendMethod!(%s)%s;
        }}.format(func.dSignature, func.signature, func.selector, func.dargs);
        }
    }
    return code;
}

/// structure presenting contract's abi
/// contains abi for contructor, functions, events
struct ContractABI
{
    string contractName = "Noname";
    string[] constructorInputs;
    ContractFunction[] functions;
    ContractEvent[] events;

    static auto load(string file)(string name = null, string[] path = []) @safe
    {
        import structjson : parseJSON;

        auto o = import(file).parseJSON;
        foreach (f; path)
        {
            o = o[f];
        }
        return ContractABI(o, name);
    }

    this(string jsontext, string name = null) @safe
    {
        import structjson : parseJSON;

        this(jsontext.parseJSON, name);
    }

    this(JSONValue abi, string name = null) @safe
    {
        if (name !is null)
        {
            contractName = name;
        }
        fromJSON(abi);
    }

    string deploySignature() const @property pure
    {
        string[] args = ["RPCConnector conn"];
        foreach (i, t; constructorInputs)
        {
            args ~= t.toDType ~ " v" ~ i.to!string;
        }
        args ~= ["ARGS argv"];
        return "deploy(ARGS...)".getSignature(args);
    }

    string deployArgs() const @property pure @safe
    {
        string[] args = ["conn"];
        foreach (i; 0 .. constructorInputs.length)
        {
            args ~= " v" ~ i.to!string;
        }
        return "deployTx".getSignature(args);
    }

    private void fromJSON(JSONValue abi) @safe pure
    {
        assert(abi.type == JSONType.array);
        JSONValue[] items = () @trusted { return abi.array; }();
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

    private void functionFromJson(JSONValue item) @safe pure
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
        keccak256(fn.selector, cast(ubyte[]) fn.signature.dup);
        functions ~= fn;
    }

    private void eventFromJson(JSONValue item) @safe pure
    {
        ContractEvent ev;
        ev.inputTypes = item[`inputs`].parseInputs;
        ev.indexedInputTypes = item[`inputs`].parseInputs!(a => a[`indexed`].boolean);
        ev.name = item[`name`].str;
        keccak256(ev.sigHash, cast(ubyte[]) ev.signature.dup);
    }

    string toString() const pure @safe nothrow @nogc
    {
        return contractName;
    }
}

private mixin template Signature()
{
    @property auto signature() @safe
    {
        return getSignature(name, inputTypes);
    }
}

private string getSignature(string name, string[] args) @safe pure
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

    string dSignature(string[] additional...) @safe pure
    {
        string[] args = [];
        foreach (i, type; inputTypes)
        {
            args ~= type.toDType ~ " v" ~ i.to!string;
        }
        args ~= additional;
        return name.getSignature(args);
    }

    private string dargs(string[] additional...) @safe pure
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

private string parseOutput(JSONValue outputs) @safe pure
{
    string[] outputTypes = [];
    JSONValue[] outputsObjs = () @trusted { return outputs.array; }();
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

private string[] parseInputs(alias filter = null)(JSONValue inputs) @safe pure
{
    import std.traits : isCallable;

    string[] inputTypes = [];
    assert(inputs.type == JSONType.array);
    foreach (JSONValue input; ()@trusted { return inputs.array; }())
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

private string parseTuple(JSONValue components) @safe pure
{
    string[] typesToJoin = [];
    foreach (type; ()@trusted { return components.array; }())
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

private string toDType(string SolType) @safe pure
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

@("type convertor toDType")
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
