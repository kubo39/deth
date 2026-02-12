module deth.contract;

import core.sync: Mutex;
import std.algorithm : canFind;
import std.array : replace, join;
import std.bigint : BigInt;
import std.conv : to;
import std.digest : toHexString;
import std.logger;
import std.string : indexOf, format;
import std.sumtype;
import std.typecons : Tuple;

import deth.rpcconnector;
import deth.util.abi : encode, decode;
import deth.util.transaction;
import deth.util.types;

import keccak : keccak256;
import structjson;


alias Selector = ubyte[4];

/// Alias for Contract without ABI
alias NonABIContract = Contract!();

///     
/// Params: 
///   abi = abi of contract  
class Contract(ContractABI abi = ContractABI.init)
{
    ///
    Address address;
    private RPCConnector conn;
    ///
    static Mutex __bytecodeMutex;
    ///
    __gshared bytes bytecode;
    ///
    __gshared string bytecode_s;
    ///
    __gshared size_t[string] spaceholders;

    ///
    this(RPCConnector conn, Address addr)
    {
        this.conn = conn;
        this.address = addr;
    }

    version (unittest)
    {
        debug pragma(msg, allFunctions(abi));
        debug pragma(msg, allEvents(abi));
    }
    mixin(allFunctions(abi));
    mixin(allEvents(abi));

    /// Sends transaction for deploy contract
    static auto deployTx(ARGS...)(RPCConnector conn, ARGS argv)
    {
        __lockMutex;
        assert(bytecode.length, "bytecode should be set");
        LegacyTransaction legacyTx;
        bytes argvEncoded = [];
        static if (argv.length > 0)
        {
            argvEncoded = encode(argv);
        }
        legacyTx.data = bytecode ~ argvEncoded;
        __unlockMutex;
        SendableTransaction tx = SendableLegacyTransaction(legacyTx, conn);
        return tx;
    }

    override string toString() const
    {
        return " Contract on 0x" ~ address.convTo!string;
    }

    ///
    auto callMethod(Selector selector, ARGS...)(Address from, BigInt value, ARGS argv)
    {
        LegacyTransaction legacyTx;
        legacyTx.data = selector[];
        legacyTx.value = value;
        legacyTx.from = from;
        static if (ARGS.length != 0)
            legacyTx.data = selector[] ~ encode(argv);
        legacyTx.to = this.address;
        Transaction tx = legacyTx;
        return conn.call(tx, BlockNumber.LATEST);
    }

    ///
    auto sendMethod(Selector selector, ARGS...)(ARGS argv)
    {
        LegacyTransaction legacyTx;
        legacyTx.data = selector[];
        legacyTx.to = this.address;
        static if (ARGS.length != 0)
            legacyTx.data = selector[] ~ encode(argv);
        SendableTransaction tx = SendableLegacyTransaction(legacyTx, conn);
        return tx;
    }

    ///
    auto callMethodS(string signature, Result = void, ARGS...)(ARGS argv)
    {
        static immutable selector = keccak256(cast(ubyte[]) signature)[0 .. 4];
        auto data = callMethod!selector(Address.init, 0.BigInt, argv);
        logCall(signature);
        static if (is(Result == void))
            return data;
        else
            return data.decode!(Result);
    }

    ///
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

    ///
    static void link(string contractName, Address addr)
    {
        __lockMutex;
        if (!spaceholders.keys.canFind(contractName))
            return;
        auto offset = spaceholders[contractName];
        auto spaceholder = bytecode_s[offset .. offset + 40];
        bytecode_s = bytecode_s.replace(spaceholder, addr.convTo!string);
        if(!bytecode_s.canFind("_$")){
            bytecode = bytecode_s.convTo!bytes;
        }
        scope(exit)__unlockMutex;
    }
    ///
    static void __lockMutex(){
        if(__bytecodeMutex)__bytecodeMutex.lock;
    }
    ///
    static void __unlockMutex(){
        if(__bytecodeMutex)__bytecodeMutex.unlock;
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
            return callMethod!(%s)%s.decode!(%s);
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

private string allEvents(ContractABI abi)
{
    string code = "";
    if (abi == ContractABI.init)
        return code;

    foreach (ev; abi.events)
    {
        // Generate event struct
        code ~= "struct " ~ ev.name ~ "Event {";
        foreach (i, t; ev.indexedInputTypes)
            code ~= t.toDType ~ " indexed" ~ i.to!string ~ ";";
        foreach (i, t; ev.dataInputTypes)
            code ~= t.toDType ~ " data" ~ i.to!string ~ ";";
        code ~= "}";

        // Generate decode method
        code ~= "static " ~ ev.name ~ "Event decode" ~ ev.name ~ "Event(Log log) @trusted {";
        code ~= "import deth.util.abi : decode;";
        code ~= ev.name ~ "Event result;";

        // Decode indexed parameters from topics[1..]
        foreach (i, t; ev.indexedInputTypes)
        {
            auto dType = t.toDType;
            auto topicIdx = (i + 1).to!string;
            code ~= "result.indexed" ~ i.to!string ~ " = "
                ~ "(cast(ubyte[32]) log.topics[" ~ topicIdx ~ "]).decode!(" ~ dType ~ ");";
        }

        // Decode non-indexed parameters from data
        if (ev.dataInputTypes.length == 1)
        {
            auto dType = ev.dataInputTypes[0].toDType;
            code ~= "result.data0 = (cast(ubyte[]) log.data).decode!(" ~ dType ~ ");";
        }
        else if (ev.dataInputTypes.length > 1)
        {
            string tupleTypes;
            foreach (i, t; ev.dataInputTypes)
            {
                if (i > 0) tupleTypes ~= ",";
                tupleTypes ~= t.toDType;
            }
            code ~= "auto decoded = (cast(ubyte[]) log.data).decode!(Tuple!(" ~ tupleTypes ~ "));";
            foreach (i, _; ev.dataInputTypes)
            {
                auto idx = i.to!string;
                code ~= "result.data" ~ idx ~ " = decoded[" ~ idx ~ "];";
            }
        }

        code ~= "return result; }";
    }

    return code;
}

/// structure presenting contract's abi
/// contains abi for contructor, functions, events
struct ContractABI
{
    ///
    string contractName = "Noname";
    ///
    string[] constructorInputs;
    ///
    ContractFunction[] functions;
    ///
    ContractEvent[] events;
    ///
    ContractError[] errors;

    ///
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

    ///
    this(string jsontext, string name = null) @safe
    {
        import structjson : parseJSON;

        this(jsontext.parseJSON, name);
    }

    ///
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

    // https://docs.soliditylang.org/en/latest/abi-spec.html#json
    private void fromJSON(JSONValue abi) @safe pure
    {
        assert(abi.type == JSONType.array);
        JSONValue[] items = () @trusted { return abi.array; }();
        foreach (item; items)
        {
            const type = item[`type`].str;
            if (`function` == type)
                functions ~= functionFromJson(item);
            if (`constructor` == type)
                constructorInputs = item[`inputs`].parseInputs;
            if (`event` == type)
                events ~= eventFromJson(item);
            if (`error` == type)
                errors ~= errorFromJson(item);
        }
    }

    private ContractFunction functionFromJson(JSONValue item) @safe pure
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
        return fn;
    }

    private ContractEvent eventFromJson(JSONValue item) @safe pure
    {
        ContractEvent event;
        event.inputTypes = item[`inputs`].parseInputs;

        JSONValue[] inputs = () @trusted { return item[`inputs`].array; }();
        foreach (input; inputs)
        {
            auto inputType = input[`type`].str;
            if (inputType.canFind("tuple"))
                inputType = inputType.replace("tuple", input[`components`].parseTuple);
            if (input[`indexed`].boolean)
                event.indexedInputTypes ~= inputType;
            else
                event.dataInputTypes ~= inputType;
        }

        event.name = item[`name`].str;
        keccak256(event.sigHash, cast(ubyte[]) event.signature.dup);
        return event;
    }

    private ContractError errorFromJson(JSONValue item) @safe pure
    {
        ContractError error;
        error.inputTypes = item[`inputs`].parseInputs;
        error.name = item[`name`].str;
        keccak256(error.sigHash, cast(ubyte[]) error.signature.dup);
        return error;
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

///
struct ContractFunction
{
    ///
    string name;
    ///
    Selector selector;
    ///
    string outputType;
    ///
    string[] inputTypes;
    ///
    Mutability mutability;
    ///
    bool payable;
    ///
    bool constant;

    mixin Signature;

    ///
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

///
struct ContractEvent
{
    ///
    string name;
    ///
    Hash sigHash;
    ///
    string[] inputTypes;
    ///
    string[] indexedInputTypes;
    ///
    string[] dataInputTypes;

    mixin Signature;
}

///
struct ContractError
{
    ///
    string name;
    ///
    Hash sigHash;
    ///
    string[] inputTypes;

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
            if (!input.filter)
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
    string DType = SolType.replace("tuple", "Tuple!");
    DType = DType.replace("address", "Address");
    /// size circle
    for (int size = 32; size > 0; size--)
    {
        auto bits = to!string(size * 8);
        auto size_s = size.to!string;
        DType = DType.replace("uint" ~ bits, "BigInt");
        DType = DType.replace("int" ~ bits, "BigInt");
        DType = DType.replace("bytes" ~ size_s, "ubyte[" ~ size_s ~ "]");
    }
    DType = DType.replace("bytes", "ubyte[]");
    return DType;
}

@("type convertor toDType")
unittest
{
    assert("int256".toDType == "BigInt", "int256".toDType);
    assert("uint256".toDType == "BigInt", "uint256".toDType);
    assert("bytes32".toDType == "ubyte[32]", "bytes32".toDType);
}

///
enum Mutability
{
    PURE = "pure",
    VIEW = "view",
    PAYABLE = "payable",
    NONPAYABLE = "nonpayable",
}

@("event: ContractEvent parses indexed and data types")
unittest
{
    // ERC-20 Transfer event ABI
    enum abi = ContractABI(`[{
        "type": "event",
        "name": "Transfer",
        "inputs": [
            {"name": "from", "type": "address", "indexed": true},
            {"name": "to", "type": "address", "indexed": true},
            {"name": "value", "type": "uint256", "indexed": false}
        ]
    }]`);

    assert(abi.events.length == 1);
    assert(abi.events[0].name == "Transfer");
    assert(abi.events[0].inputTypes == ["address", "address", "uint256"]);
    assert(abi.events[0].indexedInputTypes == ["address", "address"]);
    assert(abi.events[0].dataInputTypes == ["uint256"]);

    // Verify sigHash = keccak256("Transfer(address,address,uint256)")
    assert(abi.events[0].sigHash[0] == 0xdd);
    assert(abi.events[0].sigHash[1] == 0xf2);
    assert(abi.events[0].sigHash[2] == 0x52);
    assert(abi.events[0].sigHash[3] == 0xad);
}

@("event: decodeEvent for Transfer event")
unittest
{
    enum abi = ContractABI(`[{
        "type": "event",
        "name": "Transfer",
        "inputs": [
            {"name": "from", "type": "address", "indexed": true},
            {"name": "to", "type": "address", "indexed": true},
            {"name": "value", "type": "uint256", "indexed": false}
        ]
    }]`);

    // Construct a mock log
    Log log;

    // topic[0] = sigHash (Transfer)
    log.topics ~= abi.events[0].sigHash;

    // topic[1] = from address (padded to 32 bytes)
    Hash fromTopic;
    fromTopic[12 .. 32] = cast(ubyte[20]) "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef".convTo!Address;
    log.topics ~= fromTopic;

    // topic[2] = to address (padded to 32 bytes)
    Hash toTopic;
    toTopic[12 .. 32] = cast(ubyte[20]) "0xcafebabecafebabecafebabecafebabecafebabe".convTo!Address;
    log.topics ~= toTopic;

    // data = uint256 value (100)
    ubyte[32] data;
    data[31] = 100;
    log.data = data.dup;

    auto transfer = Contract!abi.decodeTransferEvent(log);
    assert(transfer.indexed0 == "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef".convTo!Address);
    assert(transfer.indexed1 == "0xcafebabecafebabecafebabecafebabecafebabe".convTo!Address);
    assert(transfer.data0 == BigInt(100));
}
