module deth.contract;

import std.algorithm : canFind, map;
import std.array : array, join;
import std.bigint : BigInt;
import std.conv : to;
import std.range : iota;
import std.string : indexOf, startsWith;
import std.traits : isIntegral;
import std.typecons : Tuple, Nullable;

import keccak : keccak256;

import deth.util.abi : encode, decode;
import deth.util.types;

/// Function selector (first 4 bytes of keccak256(signature))
alias Selector = ubyte[4];

/// Compile-time Solidity type descriptor
struct SolType(D, string solName)
{
    alias DType = D;
    enum string solidityName = solName;
}

/// address type
alias SolAddress = SolType!(Address, "address");

/// bool type
alias SolBool = SolType!(bool, "bool");

/// uint256 type
alias SolUint256 = SolType!(BigInt, "uint256");

/// uint128 type
alias SolUint128 = SolType!(BigInt, "uint128");

/// uint64 type
alias SolUint64 = SolType!(ulong, "uint64");

/// uint32 type
alias SolUint32 = SolType!(uint, "uint32");

/// uint16 type
alias SolUint16 = SolType!(ushort, "uint16");

/// uint8 type
alias SolUint8 = SolType!(ubyte, "uint8");

/// int256 type
alias SolInt256 = SolType!(BigInt, "int256");

/// int128 type
alias SolInt128 = SolType!(BigInt, "int128");

/// int64 type
alias SolInt64 = SolType!(long, "int64");

/// int32 type
alias SolInt32 = SolType!(int, "int32");

/// int16 type
alias SolInt16 = SolType!(short, "int16");

/// int8 type
alias SolInt8 = SolType!(byte, "int8");

/// bytes32 type
alias SolBytes32 = SolType!(ubyte[32], "bytes32");

/// bytes type (dynamic)
alias SolBytes = SolType!(bytes, "bytes");

/// string type
alias SolString = SolType!(string, "string");

@("SolType aliases")
unittest
{
    assert(SolAddress.solidityName == "address");
    assert(SolUint256.solidityName == "uint256");
    assert(SolBool.solidityName == "bool");
    assert(SolBytes32.solidityName == "bytes32");
    assert(SolString.solidityName == "string");
}

/// Generate selector from signature at compile time
Selector computeSelector(string signature)() pure @safe
{
    static immutable Selector result = () {
        ubyte[32] hash;
        keccak256(hash, cast(const(ubyte)[]) signature);
        return cast(Selector) hash[0 .. 4];
    }();
    return result;
}

@("computeSelector")
unittest
{
    // balanceOf(address) = 0x70a08231
    enum sel1 = computeSelector!"balanceOf(address)"();
    assert(sel1 == [0x70, 0xa0, 0x82, 0x31]);

    // transfer(address,uint256) = 0xa9059cbb
    enum sel2 = computeSelector!"transfer(address,uint256)"();
    assert(sel2 == [0xa9, 0x05, 0x9c, 0xbb]);

    // approve(address,uint256) = 0x095ea7b3
    enum sel3 = computeSelector!"approve(address,uint256)"();
    assert(sel3 == [0x09, 0x5e, 0xa7, 0xb3]);
}

/// Mixin template for generating a function call struct
mixin template SolCallImpl(string sig)
{
    /// Function selector
    static immutable Selector selector = computeSelector!sig;

    /// Function signature
    enum string signature = sig;

    /// Encode calldata (selector + encoded arguments)
    bytes encodeCalldata(Args...)(Args args) const pure @safe
    {
        static if (Args.length == 0)
            return selector[].dup;
        else
            return selector[] ~ encode(args);
    }
}

@("SolCallImpl mixin")
unittest
{
    struct BalanceOfCall
    {
        mixin SolCallImpl!"balanceOf(address)";
    }

    assert(BalanceOfCall.selector == [0x70, 0xa0, 0x82, 0x31]);
    assert(BalanceOfCall.signature == "balanceOf(address)");
}

/// Mixin template for event signature hash
mixin template SolEventImpl(string sig)
{
    /// Event signature hash
    static immutable Hash signatureHash = () {
        ubyte[32] hash;
        keccak256(hash, cast(const(ubyte)[]) sig);
        return cast(Hash) hash;
    }();

    /// Event signature
    enum string signature = sig;
}

@("SolEventImpl mixin")
unittest
{
    struct TransferEvent
    {
        mixin SolEventImpl!"Transfer(address,address,uint256)";
    }

    // Transfer event signature hash
    assert(TransferEvent.signature == "Transfer(address,address,uint256)");
    assert(TransferEvent.signatureHash[0 .. 4] == [0xdd, 0xf2, 0x52, 0xad]);
}

/// Mixin template for custom error
mixin template SolErrorImpl(string sig)
{
    /// Error selector
    static immutable Selector selector = computeSelector!sig;

    /// Error signature
    enum string signature = sig;
}

/// Call builder for constructing and executing contract calls
struct CallBuilder(Conn, Return)
{
    private Conn conn;
    private Address target;
    private bytes calldata;
    private BigInt _value = BigInt(0);
    private Nullable!Address _from;

    /// Construct a CallBuilder
    this(Conn conn, Address target, bytes calldata)
    {
        this.conn = conn;
        this.target = target;
        this.calldata = calldata;
    }

    /// Set transaction value (for payable functions)
    ref CallBuilder value(T)(T v) return
        if (isIntegral!T || is(T == BigInt))
    {
        static if (is(T == BigInt))
            this._value = v;
        else
            this._value = BigInt(v);
        return this;
    }

    /// Set sender address
    ref CallBuilder from(Address addr) return
    {
        this._from = addr;
        return this;
    }

    /// Execute eth_call
    Return call()() @safe
        if (!is(Return == void))
    {
        import deth.util.transaction : LegacyTransaction, Transaction;

        LegacyTransaction tx;
        tx.to = target;
        tx.value = _value;
        tx.data = calldata;
        if (!_from.isNull)
            tx.from = _from.get;

        auto result = conn.call(Transaction(tx));
        return result.decode!Return;
    }

    /// Execute eth_call for void return
    void call()() @safe
        if (is(Return == void))
    {
        import deth.util.transaction : LegacyTransaction, Transaction;

        LegacyTransaction tx;
        tx.to = target;
        tx.value = _value;
        tx.data = calldata;
        if (!_from.isNull)
            tx.from = _from.get;

        conn.call(Transaction(tx));
    }

    /// Get raw calldata
    bytes getCalldata() const pure @safe
    {
        return calldata.dup;
    }

    /// Send transaction and return hash
    Hash send()() @safe
    {
        return sendable().send();
    }

    /// Get a SendableTransaction for more control
    auto sendable()() @safe
    {
        import deth.util.transaction : LegacyTransaction, SendableLegacyTransaction;

        LegacyTransaction tx;
        tx.to = target;
        tx.value = _value;
        tx.data = calldata;
        if (!_from.isNull)
            tx.from = _from.get;

        return SendableLegacyTransaction(tx, conn);
    }
}

/// Create a CallBuilder for a function call
CallBuilder!(Conn, Return) makeCall(Return, Conn, Args...)(
    Conn conn,
    Address target,
    Selector selector,
    Args args
) @safe
{
    bytes calldata;
    static if (Args.length == 0)
        calldata = selector[].dup;
    else
        calldata = selector[] ~ encode(args);

    return CallBuilder!(Conn, Return)(conn, target, calldata);
}

/// Parsed ABI function for code generation
struct ParsedFunction
{
    string name;
    string[] inputTypes;
    string[] inputNames;
    string outputType;
    bool isView;
    bool isPure;
    bool isPayable;

    /// Get the Solidity function signature
    string signature() const pure @safe
    {
        return name ~ "(" ~ inputTypes.join(",") ~ ")";
    }
}

/// Parsed ABI event for code generation
struct ParsedEvent
{
    string name;
    string[] inputTypes;
    string[] inputNames;
    bool[] indexed;

    /// Get the Solidity event signature
    string signature() const pure @safe
    {
        return name ~ "(" ~ inputTypes.join(",") ~ ")";
    }
}

/// Parse JSON ABI at compile time
struct ParsedABI
{
    string contractName;
    ParsedFunction[] functions;
    ParsedEvent[] events;
    string[] constructorInputTypes;
}

/// Parse ABI JSON string at compile time (uses structjson for CTFE support)
ParsedABI parseABI(string jsonStr, string name = "Contract") pure @trusted
{
    import structjson : parseJSON, JSONValue, JSONType;

    // Helper to parse a single ABI type, handling tuple with components
    string parseAbiType(JSONValue typeObj)
    {
        if ("type" !in typeObj)
            throw new Exception("Malformed ABI: entry is missing the \"type\" field");
        string typeStr = typeObj["type"].str;

        // Handle tuple type with components
        if (typeStr == "tuple" || typeStr.startsWith("tuple["))
        {
            string tupleType = "(";
            if ("components" in typeObj && typeObj["components"].type == JSONType.array)
            {
                string[] componentTypes;
                foreach (comp; typeObj["components"].array)
                {
                    componentTypes ~= parseAbiType(comp);
                }
                tupleType ~= componentTypes.join(",");
            }
            tupleType ~= ")";

            // Handle tuple arrays like tuple[], tuple[3], tuple[10], tuple[][]
            enum tuplePrefix = "tuple";
            if (typeStr.length > tuplePrefix.length)
            {
                // Extract array suffix after "tuple"
                tupleType ~= typeStr[tuplePrefix.length .. $];
            }

            return tupleType;
        }

        return typeStr;
    }

    ParsedABI result;
    result.contractName = name;

    auto json = parseJSON(jsonStr);
    if (json.type != JSONType.array)
        return result;

    foreach (item; json.array)
    {
        string itemType = item["type"].str;

        if (itemType == "function")
        {
            ParsedFunction func;
            func.name = item["name"].str;

            // Parse inputs
            if ("inputs" in item && item["inputs"].type == JSONType.array)
            {
                foreach (input; item["inputs"].array)
                {
                    func.inputTypes ~= parseAbiType(input);
                    func.inputNames ~= ("name" in input) ? input["name"].str : "";
                }
            }

            // Parse outputs
            if ("outputs" in item && item["outputs"].type == JSONType.array)
            {
                auto outputs = item["outputs"].array;
                if (outputs.length == 1)
                {
                    func.outputType = parseAbiType(outputs[0]);
                }
                else if (outputs.length > 1)
                {
                    string[] types;
                    foreach (output; outputs)
                        types ~= parseAbiType(output);
                    func.outputType = "(" ~ types.join(",") ~ ")";
                }
            }

            // Parse state mutability
            if ("stateMutability" in item)
            {
                string mutability = item["stateMutability"].str;
                func.isView = (mutability == "view");
                func.isPure = (mutability == "pure");
                func.isPayable = (mutability == "payable");
            }
            else
            {
                // Fallback for older ABI formats (pre-Solidity 0.4.16)
                // that use "constant" and "payable" fields instead of "stateMutability"
                bool isConstant = ("constant" in item && item["constant"].boolean);
                bool isPayable = ("payable" in item && item["payable"].boolean);

                // Reject invalid combination
                assert(!(isConstant && isPayable),
                    "Invalid ABI: state mutability cannot be both `constant` and `payable`");

                if (isConstant)
                    func.isView = true;
                if (isPayable)
                    func.isPayable = true;
            }

            result.functions ~= func;
        }
        else if (itemType == "event")
        {
            ParsedEvent evt;
            evt.name = item["name"].str;

            if ("inputs" in item && item["inputs"].type == JSONType.array)
            {
                foreach (input; item["inputs"].array)
                {
                    evt.inputTypes ~= parseAbiType(input);
                    evt.inputNames ~= ("name" in input) ? input["name"].str : "";
                    evt.indexed ~= ("indexed" in input) ? input["indexed"].boolean : false;
                }
            }

            result.events ~= evt;
        }
        else if (itemType == "constructor")
        {
            if ("inputs" in item && item["inputs"].type == JSONType.array)
            {
                foreach (input; item["inputs"].array)
                {
                    result.constructorInputTypes ~= parseAbiType(input);
                }
            }
        }
    }
    return result;
}

@("parseABI basic")
unittest
{
    enum testABI = `[
        {
            "type": "function",
            "name": "balanceOf",
            "inputs": [{"name": "owner", "type": "address"}],
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "transfer",
            "inputs": [
                {"name": "to", "type": "address"},
                {"name": "amount", "type": "uint256"}
            ],
            "outputs": [{"name": "", "type": "bool"}],
            "stateMutability": "nonpayable"
        },
        {
            "type": "event",
            "name": "Transfer",
            "inputs": [
                {"name": "from", "type": "address", "indexed": true},
                {"name": "to", "type": "address", "indexed": true},
                {"name": "value", "type": "uint256", "indexed": false}
            ]
        }
    ]`;

    enum abi = parseABI(testABI, "ERC20");

    assert(abi.contractName == "ERC20");
    assert(abi.functions.length == 2);
    assert(abi.events.length == 1);

    assert(abi.functions[0].name == "balanceOf");
    assert(abi.functions[0].inputTypes == ["address"]);
    assert(abi.functions[0].outputType == "uint256");
    assert(abi.functions[0].isView == true);
    assert(abi.functions[0].signature == "balanceOf(address)");

    assert(abi.functions[1].name == "transfer");
    assert(abi.functions[1].inputTypes == ["address", "uint256"]);
    assert(abi.functions[1].outputType == "bool");
    assert(abi.functions[1].isView == false);

    assert(abi.events[0].name == "Transfer");
    assert(abi.events[0].inputTypes == ["address", "address", "uint256"]);
    assert(abi.events[0].indexed == [true, true, false]);
}

@("parseABI with legacy constant/payable fields")
unittest
{
    // Test older ABI format using "constant" field (pre-Solidity 0.4.16)
    enum legacyABI = `[
        {
            "type": "function",
            "name": "balanceOf",
            "inputs": [{"name": "owner", "type": "address"}],
            "outputs": [{"name": "", "type": "uint256"}],
            "constant": true
        },
        {
            "type": "function",
            "name": "transfer",
            "inputs": [
                {"name": "to", "type": "address"},
                {"name": "amount", "type": "uint256"}
            ],
            "outputs": [{"name": "", "type": "bool"}],
            "constant": false
        },
        {
            "type": "function",
            "name": "deposit",
            "inputs": [],
            "outputs": [],
            "payable": true
        }
    ]`;

    enum abi = parseABI(legacyABI);

    // constant: true should be treated as view
    assert(abi.functions[0].name == "balanceOf");
    assert(abi.functions[0].isView == true);
    assert(abi.functions[0].isPure == false);
    assert(abi.functions[0].isPayable == false);

    // constant: false should not set isView
    assert(abi.functions[1].name == "transfer");
    assert(abi.functions[1].isView == false);

    // payable: true should set isPayable
    assert(abi.functions[2].name == "deposit");
    assert(abi.functions[2].isPayable == true);
    assert(abi.functions[2].isView == false);
}

@("parseABI with tuple types")
unittest
{
    // Test tuple input (struct parameter)
    enum tupleInputABI = `[
        {
            "type": "function",
            "name": "setPosition",
            "inputs": [{
                "name": "pos",
                "type": "tuple",
                "components": [
                    {"name": "x", "type": "uint256"},
                    {"name": "y", "type": "uint256"}
                ]
            }],
            "outputs": [],
            "stateMutability": "nonpayable"
        }
    ]`;

    enum abi1 = parseABI(tupleInputABI);
    assert(abi1.functions[0].inputTypes == ["(uint256,uint256)"]);
    assert(abi1.functions[0].signature == "setPosition((uint256,uint256))");

    // Test tuple output (struct return)
    enum tupleOutputABI = `[
        {
            "type": "function",
            "name": "getPosition",
            "inputs": [],
            "outputs": [{
                "name": "",
                "type": "tuple",
                "components": [
                    {"name": "x", "type": "uint256"},
                    {"name": "y", "type": "uint256"}
                ]
            }],
            "stateMutability": "view"
        }
    ]`;

    enum abi2 = parseABI(tupleOutputABI);
    assert(abi2.functions[0].outputType == "(uint256,uint256)");

    // Test multiple outputs (implicit tuple)
    enum multiOutputABI = `[
        {
            "type": "function",
            "name": "getValues",
            "inputs": [],
            "outputs": [
                {"name": "a", "type": "uint256"},
                {"name": "b", "type": "address"}
            ],
            "stateMutability": "view"
        }
    ]`;

    enum abi3 = parseABI(multiOutputABI);
    assert(abi3.functions[0].outputType == "(uint256,address)");

    // Test nested tuple
    enum nestedTupleABI = `[
        {
            "type": "function",
            "name": "getComplex",
            "inputs": [],
            "outputs": [{
                "name": "",
                "type": "tuple",
                "components": [
                    {"name": "id", "type": "uint256"},
                    {
                        "name": "inner",
                        "type": "tuple",
                        "components": [
                            {"name": "addr", "type": "address"},
                            {"name": "flag", "type": "bool"}
                        ]
                    }
                ]
            }],
            "stateMutability": "view"
        }
    ]`;

    enum abi4 = parseABI(nestedTupleABI);
    assert(abi4.functions[0].outputType == "(uint256,(address,bool))");

    // Test tuple array
    enum tupleArrayABI = `[
        {
            "type": "function",
            "name": "getPositions",
            "inputs": [],
            "outputs": [{
                "name": "",
                "type": "tuple[]",
                "components": [
                    {"name": "x", "type": "uint256"},
                    {"name": "y", "type": "uint256"}
                ]
            }],
            "stateMutability": "view"
        }
    ]`;

    enum abi5 = parseABI(tupleArrayABI);
    assert(abi5.functions[0].outputType == "(uint256,uint256)[]");

    // Test fixed-size tuple array with multi-digit size (tuple[10])
    enum tupleFixedArrayABI = `[
        {
            "type": "function",
            "name": "getFixedPositions",
            "inputs": [],
            "outputs": [{
                "name": "",
                "type": "tuple[10]",
                "components": [
                    {"name": "x", "type": "uint256"},
                    {"name": "y", "type": "uint256"}
                ]
            }],
            "stateMutability": "view"
        }
    ]`;

    enum abi6 = parseABI(tupleFixedArrayABI);
    assert(abi6.functions[0].outputType == "(uint256,uint256)[10]");

    // Test nested tuple array (tuple[][])
    enum tupleNestedArrayABI = `[
        {
            "type": "function",
            "name": "getNestedPositions",
            "inputs": [],
            "outputs": [{
                "name": "",
                "type": "tuple[][]",
                "components": [
                    {"name": "x", "type": "uint256"},
                    {"name": "y", "type": "uint256"}
                ]
            }],
            "stateMutability": "view"
        }
    ]`;

    enum abi7 = parseABI(tupleNestedArrayABI);
    assert(abi7.functions[0].outputType == "(uint256,uint256)[][]");
}

/// Split tuple type string into component types, handling nested tuples
/// Example: "(uint256,address)" -> ["uint256", "address"]
/// Example: "(uint256,(address,bool))" -> ["uint256", "(address,bool)"]
string[] splitTupleTypes(string inner) pure @safe
{
    string[] result;
    int depth = 0;
    size_t start = 0;

    foreach (i; 0 .. inner.length)
    {
        char c = inner[i];
        if (c == '(')
            depth++;
        else if (c == ')')
        {
            depth--;
            if (depth < 0)
                throw new Exception("Malformed ABI tuple type: unmatched ')' in \"" ~ inner ~ "\"");
        }
        else if (c == ',' && depth == 0)
        {
            result ~= inner[start .. i];
            start = i + 1;
        }
    }
    if (depth != 0)
        throw new Exception("Malformed ABI tuple type: unmatched '(' in \"" ~ inner ~ "\"");
    if (start < inner.length)
        result ~= inner[start .. $];

    return result;
}

@("splitTupleTypes")
unittest
{
    assert(splitTupleTypes("uint256,address") == ["uint256", "address"]);
    assert(splitTupleTypes("uint256") == ["uint256"]);
    assert(splitTupleTypes("uint256,(address,bool)") == ["uint256", "(address,bool)"]);
    assert(splitTupleTypes("(uint256,uint256),address,(bool,bytes32)") == [
        "(uint256,uint256)", "address", "(bool,bytes32)"
    ]);
    assert(splitTupleTypes("") == []);
}

/// Convert Solidity type to D type string
string solTypeToDType(string solType) pure @safe
{
    import std.string : startsWith, endsWith;
    import std.algorithm : canFind;

    // Handle tuple types like "(uint256,address)"
    if (solType.startsWith("(") && solType.endsWith(")"))
    {
        string inner = solType[1 .. $ - 1];
        if (inner.length == 0)
            return "Tuple!()";

        string[] componentTypes = splitTupleTypes(inner);
        string[] dTypes;
        foreach (t; componentTypes)
            dTypes ~= solTypeToDType(t);
        return "Tuple!(" ~ dTypes.join(", ") ~ ")";
    }

    // Handle arrays
    if (solType.endsWith("[]"))
    {
        string baseType = solType[0 .. $ - 2];
        return solTypeToDType(baseType) ~ "[]";
    }

    // Handle fixed-size arrays like uint256[3]
    if (solType.canFind("[") && solType.endsWith("]"))
    {
        auto bracketIdx = solType.indexOf('[');
        string baseType = solType[0 .. bracketIdx];
        string size = solType[bracketIdx + 1 .. $ - 1];
        return solTypeToDType(baseType) ~ "[" ~ size ~ "]";
    }

    // Basic type mappings
    if (solType == "address") return "Address";
    if (solType == "bool") return "bool";
    if (solType == "string") return "string";
    if (solType == "bytes") return "bytes";

    // uint types - use native types where possible
    if (solType.startsWith("uint"))
    {
        if (solType == "uint8") return "ubyte";
        if (solType == "uint16") return "ushort";
        if (solType == "uint32") return "uint";
        if (solType == "uint64") return "ulong";
        // uint128, uint256, etc. use BigInt
        return "BigInt";
    }

    // int types - use native types where possible
    if (solType.startsWith("int"))
    {
        if (solType == "int8") return "byte";
        if (solType == "int16") return "short";
        if (solType == "int32") return "int";
        if (solType == "int64") return "long";
        // int128, int256, etc. use BigInt
        return "BigInt";
    }

    // bytes1 to bytes32
    if (solType.startsWith("bytes") && solType.length > 5)
    {
        import std.ascii : isDigit;
        import std.algorithm : all;

        string size = solType[5 .. $];
        if (size.all!isDigit)
            return "ubyte[" ~ size ~ "]";
    }

    // Unrecognized type - fail at compile time with clear error message
    assert(false, "Unsupported Solidity type: " ~ solType);
}

@("solTypeToDType")
unittest
{
    assert(solTypeToDType("address") == "Address");
    assert(solTypeToDType("bool") == "bool");
    assert(solTypeToDType("bytes32") == "ubyte[32]");
    assert(solTypeToDType("bytes") == "bytes");
    assert(solTypeToDType("string") == "string");

    // Unsigned integers - native types for 64-bit and smaller
    assert(solTypeToDType("uint8") == "ubyte");
    assert(solTypeToDType("uint16") == "ushort");
    assert(solTypeToDType("uint32") == "uint");
    assert(solTypeToDType("uint64") == "ulong");
    assert(solTypeToDType("uint128") == "BigInt");
    assert(solTypeToDType("uint256") == "BigInt");

    // Signed integers - native types for 64-bit and smaller
    assert(solTypeToDType("int8") == "byte");
    assert(solTypeToDType("int16") == "short");
    assert(solTypeToDType("int32") == "int");
    assert(solTypeToDType("int64") == "long");
    assert(solTypeToDType("int128") == "BigInt");
    assert(solTypeToDType("int256") == "BigInt");

    // Arrays
    assert(solTypeToDType("address[]") == "Address[]");
    assert(solTypeToDType("uint256[]") == "BigInt[]");
    assert(solTypeToDType("uint32[]") == "uint[]");

    // Tuple types
    assert(solTypeToDType("(uint256,address)") == "Tuple!(BigInt, Address)");
    assert(solTypeToDType("(uint256,uint256)") == "Tuple!(BigInt, BigInt)");
    assert(solTypeToDType("(bool)") == "Tuple!(bool)");
    assert(solTypeToDType("()") == "Tuple!()");

    // Nested tuples
    assert(solTypeToDType("(uint256,(address,bool))") == "Tuple!(BigInt, Tuple!(Address, bool))");

    // Tuple arrays
    assert(solTypeToDType("(uint256,address)[]") == "Tuple!(BigInt, Address)[]");
}

/// Generate D code for a contract method
string generateMethodCode(const ParsedFunction func) pure @safe
{
    string code;

    // Build parameter list
    string[] params;
    foreach (i, inputType; func.inputTypes)
    {
        string dType = solTypeToDType(inputType);
        string paramName = (func.inputNames.length > i && func.inputNames[i].length > 0)
            ? func.inputNames[i]
            : "arg" ~ i.to!string;
        params ~= dType ~ " " ~ paramName;
    }

    // Build argument list for encode
    string[] args;
    foreach (i, _; func.inputTypes)
    {
        string paramName = (func.inputNames.length > i && func.inputNames[i].length > 0)
            ? func.inputNames[i]
            : "arg" ~ i.to!string;
        args ~= paramName;
    }

    string returnType = func.outputType.length > 0 ? solTypeToDType(func.outputType) : "void";
    string selector = `computeSelector!"` ~ func.signature ~ `"()`;

    if (func.isView || func.isPure)
    {
        // View/pure function - returns CallBuilder for .call()
        code ~= `    auto ` ~ func.name ~ `(` ~ params.join(", ") ~ `) @safe {
        return makeCall!(` ~ returnType ~ `)(conn, address, ` ~ selector;
        if (args.length > 0)
            code ~= `, ` ~ args.join(", ");
        code ~= `);
    }
`;
    }
    else
    {
        // State-changing function - returns CallBuilder for .send()
        code ~= `    auto ` ~ func.name ~ `(` ~ params.join(", ") ~ `) @safe {
        return makeCall!(` ~ returnType ~ `)(conn, address, ` ~ selector;
        if (args.length > 0)
            code ~= `, ` ~ args.join(", ");
        code ~= `);
    }
`;
    }
    return code;
}

@("generateMethodCode")
unittest
{
    ParsedFunction func;
    func.name = "balanceOf";
    func.inputTypes = ["address"];
    func.inputNames = ["owner"];
    func.outputType = "uint256";
    func.isView = true;

    string code = generateMethodCode(func);

    assert(code.canFind("balanceOf"));
    assert(code.canFind("Address owner"));
    assert(code.canFind("BigInt"));
    assert(code.canFind(`computeSelector!"balanceOf(address)"`));
}

/// Mixin template for defining a contract from JSON ABI (CTFE supported)
mixin template DefineContract(string abiJson, string contractName = "Contract")
{
    import core.sync.mutex : Mutex;
    import std.bigint : BigInt;
    import std.concurrency : initOnce;
    import std.typecons : Tuple;
    import deth.util.abi : encode;
    import deth.util.transaction : LegacyTransaction, SendableLegacyTransaction;

    /// Parsed ABI at compile time
    enum _parsedABI = parseABI(abiJson, contractName);

    /// Bytecode storage
    private __gshared bytes _bytecode;
    private __gshared Mutex _bytecodeMutex;

    /// Initialize mutex exactly once (thread-safe via initOnce)
    private static Mutex getBytecodeMutex() @trusted
    {
        return initOnce!_bytecodeMutex(new Mutex());
    }

    /// Set bytecode for deployment (thread-safe)
    static void setBytecode(bytes code) @trusted
    {
        auto mtx = getBytecodeMutex();
        mtx.lock();
        scope(exit) mtx.unlock();
        _bytecode = code;
    }

    /// Get bytecode (thread-safe)
    static bytes getBytecode() @trusted
    {
        auto mtx = getBytecodeMutex();
        mtx.lock();
        scope(exit) mtx.unlock();
        return _bytecode;
    }

    /// Create a contract instance class template
    static class ContractInstance(Conn)
    {
        Conn conn;
        Address address;

        this(Conn conn, Address addr)
        {
            this.conn = conn;
            this.address = addr;
        }

        /// Get contract address as string
        override string toString() const
        {
            return contractName ~ " at 0x" ~ address.convTo!string;
        }

        // Generate methods for each function in ABI
        static foreach (func; _parsedABI.functions)
        {
            mixin(generateMethodCode(func));
        }
    }

    /// Helper to create a contract instance at an address
    static auto at(Conn)(Conn conn, Address addr)
    {
        return new ContractInstance!Conn(conn, addr);
    }

    /// Create deployment transaction
    static auto deployTx(Conn, ARGS...)(Conn conn, ARGS args) @trusted
    {
        auto bytecode = getBytecode();
        assert(bytecode.length > 0, "Bytecode not set. Call setBytecode first.");

        LegacyTransaction tx;
        static if (ARGS.length > 0)
            tx.data = bytecode ~ encode(args);
        else
            tx.data = bytecode;

        return SendableLegacyTransaction(tx, conn);
    }

    /// Deploy contract and return instance
    static auto deploy(Conn, ARGS...)(Conn conn, ARGS args) @trusted
    {
        auto sendable = deployTx(conn, args);
        auto txHash = sendable.send();
        auto receipt = conn.waitForTransactionReceipt(txHash);
        assert(!receipt.contractAddress.isNull, "Contract deployment failed");
        return new ContractInstance!Conn(conn, receipt.contractAddress.get);
    }
}

@("DefineContract mixin")
unittest
{
    enum testABI = `[
        {
            "type": "function",
            "name": "getValue",
            "inputs": [],
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "setValue",
            "inputs": [{"name": "value", "type": "uint256"}],
            "outputs": [],
            "stateMutability": "nonpayable"
        }
    ]`;

    struct TestContract
    {
        mixin DefineContract!(testABI, "SimpleStorage");
    }

    static assert(TestContract._parsedABI.contractName == "SimpleStorage");
    static assert(TestContract._parsedABI.functions.length == 2);
    static assert(TestContract._parsedABI.functions[0].name == "getValue");
    static assert(TestContract._parsedABI.functions[1].name == "setValue");

    static assert(is(TestContract.ContractInstance!Object));
}

/// Load ABI from file at compile time
template loadABI(string file)
{
    enum loadABI = import(file);
}

/// Generic contract for dynamic method calls
class GenericContract(Conn)
{
    Conn conn;
    Address address;

    this(Conn conn, Address addr)
    {
        this.conn = conn;
        this.address = addr;
    }

    /// Call a view/pure function by signature string and return the result directly
    /// Example: contract.call!("balanceOf(address)", BigInt)(ownerAddr)
    Return call(string signature, Return, ARGS...)(ARGS args) @safe
        if (!is(Return == void))
    {
        enum selector = computeSelector!signature();
        return makeCall!Return(conn, address, selector, args).call();
    }

    /// Send a state-changing transaction by signature string and return the tx hash directly
    /// Example: contract.send!"transfer(address,uint256)"(to, amount)
    auto send(string signature, ARGS...)(ARGS args) @safe
    {
        enum selector = computeSelector!signature();
        return makeCall!(void)(conn, address, selector, args).send();
    }

    /// Get a CallBuilder for method chaining (.from(), .value(), etc.)
    /// Example: contract.prepare!("balanceOf(address)", BigInt)(ownerAddr).from(addr).call()
    /// Example: contract.prepare!"set(int32)"(34).from(accounts[0]).send()
    auto prepare(string signature, Return = void, ARGS...)(ARGS args) @safe
    {
        enum selector = computeSelector!signature();
        return makeCall!Return(conn, address, selector, args);
    }

    /// Call with explicit selector
    auto callWithSelector(Return = void, ARGS...)(Selector selector, ARGS args) @safe
    {
        return makeCall!Return(conn, address, selector, args);
    }

    override string toString() const
    {
        return "GenericContract at 0x" ~ address.convTo!string;
    }
}

/// Simpler function to generate a contract class directly
string generateContractCode(string abiJson, string className) pure @safe
{
    auto abi = parseABI(abiJson, className);

    string code = "class " ~ className ~ "(Conn) {\n";
    code ~= "    Conn conn;\n";
    code ~= "    Address address;\n\n";
    code ~= "    this(Conn conn, Address addr) {\n";
    code ~= "        this.conn = conn;\n";
    code ~= "        this.address = addr;\n";
    code ~= "    }\n\n";

    foreach (func; abi.functions)
    {
        code ~= generateMethodCode(func);
    }

    code ~= "}\n";
    return code;
}

@("GenericContract.call directly returns result")
unittest
{
    import std.bigint : BigInt;

    // Mock connection type for compile-time checks
    static struct MockConn
    {
        import deth.util.transaction : Transaction;

        bytes call(Transaction tx) @safe
        {
            // Return encoded bool (true) - 32 bytes with 1 in last position
            ubyte[32] result;
            result[31] = 1;
            return result[].dup;
        }
    }

    auto conn = MockConn();
    auto contract = new GenericContract!MockConn(conn, Address.init);

    // call directly returns the decoded result
    bool result = contract.call!("transfer(address,uint256)", bool)(Address.init, BigInt(100));
    assert(result == true);

    // prepare returns a CallBuilder for method chaining
    auto builder = contract.prepare!("approve(address,uint256)", bool)(Address.init, BigInt(100));
    auto calldata = builder.getCalldata();
    assert(calldata.length == 4 + 32 + 32); // selector + 2 args
}
