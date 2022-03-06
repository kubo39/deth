module deth.util.abi;

import std.traits : isInstanceOf, isIntegral, isBoolean, isStaticArray,
    isDynamicArray, FieldNameTuple, isAggregateType, Unconst;
import std : ElementType;
import std : to, writeln, writef, text;
import std : BigInt, toHex, replace;
import std : map, join, fold;
import std : array, iota;
import deth.util.types;

/// SLOT SIZE 32 bytes
enum SS = 32;

bytes encode(ARGS...)(ARGS args_)
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

struct EncodingResult
{
    bytes value = []; /// static encoded
    bytes data = []; /// dynamic encoded

    EncodingResult opOpAssign(string op)(EncodingResult a)
    {
        static if (op == "~")
        {
            value ~= a.value;
            data ~= a.data;
            return this;
        }
    }
}

EncodingResult encodeUnit(T)(T v)
{
    EncodingResult result;
    static if (isBoolean!T || isIntegral!T)
    {
        result.value = v.BigInt.convTo!bytes.padLeft(0, SS).array;
    }
    else static if (isStaticArray!T && is(ElementType!T == Unconst!ubyte))
    {
        result.value = v[].padLeft(0, SS);
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

auto tuplelize(ARGS...)(ARGS argv)
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

auto tuplelizeT(T)(T v)
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

    void runTest(ARGS...)(string expected, ARGS argv)
    {
        import std : toHexString;

        auto encoded = encode(argv).toHexString;
        assert(expected == encoded, encoded);
        assert(expected.length % 64 == 0);
    }
}

unittest
{
    runTest("0000000000000000000000000000000000000000000000000000000000000122", 0x122);
    runTest("000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000A000000000000000000000000000000000000000000000000000000000000000E00000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000A000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000001E",
            [10], [20], [30]);
    runTest("000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000A00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000A00000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000001E0000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000A000000000000000000000000000000000000000000000000000000000000000E0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000003",
            [[10, 20], [30]], [[1], [2], [3]]);
    runTest("000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000E0000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009",
            [1, 2, 3], [4, 5, 6], [8, 9]);
    runTest("000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001A00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000C00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000A0000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001E000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000280000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000003C0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000005A0000000000000000000000000000000000000000000000000000000000000064",
            [[10, 20, 30], [40, 50, 60]], [90, 100]);
    runTest("0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000D48656C6C6F2C20776F726C642100000000000000000000000000000000000000",
            "Hello, world!");
    ubyte[20] data;
    data[19] = 0xab;
    runTest("00000000000000000000000000000000000000000000000000000000000000AB", data);
}

T decode(T)(ubyte[] data, size_t offsetShift = 0)
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
        else
            static assert(0, "Type not supported");
        return result;
    }
}

void runTestDecode(T)(T a)
{
    auto got = a.encode.decode!T;
    assert(got == a, got.to!string);

}

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
