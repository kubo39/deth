module deth.util.abi;

import std.traits : isInstanceOf, isIntegral, isBoolean, isStaticArray,
    isDynamicArray, FieldNameTuple, isAggregateType, Unconst;
import std : ElementType;
import std : to, text;
import std : BigInt, toHex, replace;
import std : map, join, fold;
import std : array, iota;
import std : Tuple;
import deth.util.types;

/// SLOT SIZE 32 bytes
enum SS = 32;

/// function for abi encoding
/// Params:
///   args_ = arguments for solidity function to be encoded
/// Returns: byte string with encoded data
bytes encode(ARGS...)(const ARGS args_) pure @safe
{
    EncodingResult res;
    auto args = args_.tuplelize;
    ulong offset = args.length * SS;
    foreach (arg; args)
    {
        auto t = arg.encodeUnit;
        if (t.value == "")
        {
            t.value ~= offset.encodeUnit.value;
        }
        res ~= t;
        offset += t.data.length;

    }
    auto encoded = res.value ~ res.data;
    return encoded;
}

private struct EncodingResult
{
    bytes value = []; /// static encoded
    bytes data = []; /// dynamic encoded

    EncodingResult opOpAssign(string op)(const EncodingResult a) pure @safe
    {
        static if (op == "~")
        {
            value ~= a.value;
            data ~= a.data;
            return this;
        }
    }
}

EncodingResult encodeUnit(T)(const T v) pure @safe
{
    EncodingResult result;
    static if(is(T == bool)){
        result.value = new ubyte[32];
        result.value[$-1] = cast(bool) v;
    }
    else static if (isBoolean!T || isIntegral!T)
    {
        result.value = v.BigInt.convTo!bytes.padLeft(0, SS);
    }
    else static if (isStaticArray!T && is(ElementType!T == Unconst!ubyte))
    {
        result.value = v.dup.padLeft(0, SS);
    }
    else static if (isStaticArray!T)
    {
        result ~= v[].map!(e => e.encodeUnit)
            .fold!((a, b) => EncodingResult(a.value ~ b.value, a.data ~ b.data));
    }
    else static if (is(T == BigInt))
    {
        result.value = v.convTo!bytes.padLeft(0, SS);
    }
    else static if(isInstanceOf!(Tuple, T)){
        foreach (t; v)
        {
            result ~= t.encodeUnit;
        }
    }
    else static if (is(T == struct))
    {
        static foreach (field; FieldNameTuple!T)
        {
            result ~= __traits(getMember, v, field).encodeUnit;
        }
    }
    else static if (isDynamicArray!T)
    {
        alias E = ElementType!T;
        result.data ~= v.length.encodeUnit.value;
        EncodingResult arr;
        auto offset = v.length * SS;
        foreach (e; v)
        {
            auto t = e.encodeUnit;
            static if (isDynamicArray!E)
            {
                // element is dynamic array
                t.value ~= offset.encodeUnit.value;
            }

            arr ~= t;
            offset += t.data.length;
        }
        auto padLen = arr.value.length;
        if (arr.value.length % SS)
            padLen += (SS - arr.value.length % SS);
        result.data ~= arr.value.padRight(0, padLen).array ~ arr.data;
    }
    else static if (is(Unconst!T == char) || is(Unconst!T == ubyte))
    {

        result.value = [v];
    }
    else
        static assert(0, "Type no supported: " ~ T.stringof);
    return result;
}

private auto tuplelize(ARGS...)(const ARGS argv) pure nothrow @safe
{
    auto code()
    {
        string[] res;
        foreach (i; 0 .. argv.length)
        {
            res ~= text(`tuplelizeT(argv[`, i, `])`);
        }
        return res.join("~ ");
    }

    mixin(`return ` ~ code ~ `;`);
}

private auto tuplelizeT(T)(const T v) pure nothrow @safe
{
    import std : tuple;

    static if (is(T == BigInt))
    {
        return tuple(v);
    }
    else static if (isStaticArray!T && is(ElementType!T == Unconst!ubyte))
    {
        return tuple(v);
    }
    else static if (isStaticArray!T)
    {
        mixin(q{
                return tuple(} ~ v.length.iota.map!q{text(`v[`, a, `]`)}.join(`, `) ~ `);`);
    }
    else static if (isInstanceOf!(Tuple, T)){
        auto code(){
            string[] res;
            foreach (i; 0..T.length)
            {
                res~=`tuplelizeT(v[` ~i.to!string ~ `])`;
            }
            return res.join("~ ");
        }
        mixin(`return `~code~`;`);
    }
    else static if (is(T == struct))
    {
        auto code()
        {
            string[] res;
            foreach (field; FieldNameTuple!T)
            {
                res ~= `tuplelizeT(v.` ~ field ~ ')';
            }
            return res.join("~ ");
        }

        mixin(`return ` ~ code ~ `;`);
    }
    else
        return tuple(v);
}

version (unittest)
{

    private void runTest(ARGS...)(const string expected, const ARGS argv)
    {
        import std : toHexString;

        auto encoded = encode(argv).toHexString;
        assert(expected == encoded, encoded);
        assert(expected.length % 64 == 0);
    }
}

@("solidity ABI encode")
unittest
{
    runTest("0000000000000000000000000000000000000000000000000000000000000122", 0x122);
    runTest("0000000000000000000000000000000000000000000000000000000000000060" ~
            "00000000000000000000000000000000000000000000000000000000000000A0" ~
            "00000000000000000000000000000000000000000000000000000000000000E0" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "000000000000000000000000000000000000000000000000000000000000000A" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "0000000000000000000000000000000000000000000000000000000000000014" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "000000000000000000000000000000000000000000000000000000000000001E",
            [10], [20], [30]);
    runTest("0000000000000000000000000000000000000000000000000000000000000040" ~
            "0000000000000000000000000000000000000000000000000000000000000140" ~
            "0000000000000000000000000000000000000000000000000000000000000002" ~
            "0000000000000000000000000000000000000000000000000000000000000040" ~
            "00000000000000000000000000000000000000000000000000000000000000A0" ~
            "0000000000000000000000000000000000000000000000000000000000000002" ~
            "000000000000000000000000000000000000000000000000000000000000000A" ~
            "0000000000000000000000000000000000000000000000000000000000000014" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "000000000000000000000000000000000000000000000000000000000000001E" ~
            "0000000000000000000000000000000000000000000000000000000000000003" ~
            "0000000000000000000000000000000000000000000000000000000000000060" ~
            "00000000000000000000000000000000000000000000000000000000000000A0" ~
            "00000000000000000000000000000000000000000000000000000000000000E0" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "0000000000000000000000000000000000000000000000000000000000000002" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "0000000000000000000000000000000000000000000000000000000000000003",
            [[10, 20], [30]], [[1], [2], [3]]);
    runTest("0000000000000000000000000000000000000000000000000000000000000060" ~
            "00000000000000000000000000000000000000000000000000000000000000E0" ~
            "0000000000000000000000000000000000000000000000000000000000000160" ~
            "0000000000000000000000000000000000000000000000000000000000000003" ~
            "0000000000000000000000000000000000000000000000000000000000000001" ~
            "0000000000000000000000000000000000000000000000000000000000000002" ~
            "0000000000000000000000000000000000000000000000000000000000000003" ~
            "0000000000000000000000000000000000000000000000000000000000000003" ~
            "0000000000000000000000000000000000000000000000000000000000000004" ~
            "0000000000000000000000000000000000000000000000000000000000000005" ~
            "0000000000000000000000000000000000000000000000000000000000000006" ~
            "0000000000000000000000000000000000000000000000000000000000000002" ~
            "0000000000000000000000000000000000000000000000000000000000000008" ~
            "0000000000000000000000000000000000000000000000000000000000000009",
            [1, 2, 3], [4, 5, 6], [8, 9]);
    runTest("0000000000000000000000000000000000000000000000000000000000000040" ~
            "00000000000000000000000000000000000000000000000000000000000001A0" ~
            "0000000000000000000000000000000000000000000000000000000000000002" ~
            "0000000000000000000000000000000000000000000000000000000000000040" ~
            "00000000000000000000000000000000000000000000000000000000000000C0" ~
            "0000000000000000000000000000000000000000000000000000000000000003" ~
            "000000000000000000000000000000000000000000000000000000000000000A" ~
            "0000000000000000000000000000000000000000000000000000000000000014" ~
            "000000000000000000000000000000000000000000000000000000000000001E" ~
            "0000000000000000000000000000000000000000000000000000000000000003" ~
            "0000000000000000000000000000000000000000000000000000000000000028" ~
            "0000000000000000000000000000000000000000000000000000000000000032" ~
            "000000000000000000000000000000000000000000000000000000000000003C" ~
            "0000000000000000000000000000000000000000000000000000000000000002" ~
            "000000000000000000000000000000000000000000000000000000000000005A" ~
            "0000000000000000000000000000000000000000000000000000000000000064",
            [[10, 20, 30], [40, 50, 60]], [90, 100]);
    runTest("0000000000000000000000000000000000000000000000000000000000000020"~
            "000000000000000000000000000000000000000000000000000000000000000D"~
            "48656C6C6F2C20776F726C642100000000000000000000000000000000000000",
        "Hello, world!");
    ubyte[20] data;
    data[19] = 0xab;
    runTest("00000000000000000000000000000000000000000000000000000000000000AB", data);
}
/// 
/// Params:
///   T    = type of decoding
///   data = bytes which presenting encoded data of type T
/// Returns: decoded result
T decode(T)(ubyte[] data, size_t offsetShift = 0) pure @safe
in (data.length % 32 == 0)
{
    static if (is(T == void))
        return;
    else
    {
        T result;
        static if (is(T == BigInt))
        {
            result = data[0 .. SS].toHexString.ox.BigInt;
        }
        else static if (isStaticArray!T && is(ElementType!T == ubyte))
        {
            result[] = data[SS - result.length .. SS];
        }
        else static if (isDynamicArray!T)
        {
            long offset = data[0 .. SS].decode!BigInt.toLong - offsetShift;
            auto arrayData = data[offset .. $];
            long len = arrayData[0 .. SS].decode!BigInt.toLong;
            foreach (i; 0 .. len)
            {
                alias Element = ElementType!T;
                // todo size of type
                enum SC = 1;
                static if (is(Element == dchar) || is(Element == char) || is(Element == ubyte))
                {
                    result ~= arrayData[SS + i .. SS + i + 1];
                }
                else
                {
                    result ~= arrayData[SS + i * SS * SC .. $].decode!Element(i * SS * SC);
                }
            }
        }
        else static if(is(T == bool)){
            result= cast(bool)data[$-1];
        }
        else static if(isInstanceOf!(Tuple, T)){

        }
        else
            static assert(0, "Type not supported");
        return result;
    }
}

private void runTestDecode(T)(T a)
{
    auto got = a.encode.decode!T;
    assert(got == a, got.to!string);

}

@("solidity ABI decode")
unittest
{
    ubyte[4] s = [1, 2, 3, 4];
    runTestDecode(10.BigInt);
    runTestDecode([2.BigInt]);
    runTestDecode([1.BigInt, 2.BigInt, 3.BigInt]);
    runTestDecode([[1.BigInt, 2.BigInt, 3.BigInt]]);
    runTestDecode([
        [10.BigInt, 20.BigInt, 30.BigInt], [40.BigInt, 50.BigInt, 60.BigInt],
        [40.BigInt, 50.BigInt, 60.BigInt]
    ]);
    runTestDecode("HelloWorld!");
    runTestDecode(s);
}
