module deth.util.types;

import std.algorithm : reverse;
import std.conv : to;
import std : toHexString;

struct FixedBytes(ulong size)
{
    static assert(size <= 32, "not supported size: " ~ size);
    ubyte[size] value;

    string toString()
    {
        return (cast(ubyte[]) value).toHexString.to!string;
    }
}

alias Address = ubyte[20];

alias bytes = ubyte[];

auto convTo(To, From)(From f)
{
    static if (is(From == Address))
    {
        static if (is(To == string))
        {
            return (cast(bytes) f).toHexString.to!string;
        }
    }
    // BigInt Part
    import std.bigint : BigInt, toHex;

    static if (is(From == BigInt))
    {
        static if (is(To == bytes))
        {
            import std : chunks, replace, map, array;
            import std.range : padLeft;

            auto hex = f.toHex.replace("_", "");
            return hex.padLeft('0', hex.length + hex.length % 2).chunks(2)
                .map!q{a.parse!ubyte(16)}.array;
        }
        static if (is(To == string))
        {
            import std.array;

            return f.toHex.replace("_", "");

        }
    }
}

unittest
{
    import std;

    ///looks like big endian coding
    bytes becodedNum = [15, 255, 255, 255, 255, 170];
    assert(`0xfffffffffaa`.BigInt.convTo!bytes == becodedNum);

    Address addr;
    assert(addr.convTo!string == join(20.iota.array.map!q{"00"}));
}

pure auto ox(T)(T t)
{
    return `0x` ~ t[];
}
