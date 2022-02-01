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

    bytes toBytes()
    {
        return value[];
    }
}

alias Address = ubyte[20];
alias Hash = ubyte[32];
alias bytes = ubyte[];

bytes hexToBytes(string s)
{
    import std : chunks, map, array, startsWith;
    import std.range : padLeft;

    if (s.startsWith(`0x`))
        s = s[2 .. $];

    return s.padLeft('0', s.length + s.length % 2).chunks(2).map!q{a.parse!ubyte(16)}.array;
}

unittest
{
    assert("0x123".hexToBytes == [0x1, 0x23]);
}

auto convTo(To, From)(From f)
{
    static if (is(From == Address))
    {
        static if (is(To == string))
        {
            return (cast(bytes) f).toHexString.to!string;
        }
        static if (is(To == bytes))
        {
            return (cast(bytes) f.dup);
        }
    }
    static if (is(From == Hash))
    {
        static if (is(To == string))
        {
            return (cast(bytes) f).toHexString.to!string;
        }
        static if (is(To == bytes))
        {
            return f[];
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
            return hex.padLeft('0', hex.length + hex.length % 2).to!string.hexToBytes;
        }
        static if (is(To == string))
        {
            import std.array;

            return f.toHex.replace("_", "");

        }
    }
    static if (is(From == string))
    {
        static if (is(To == Address))
        {
            Address[] v = cast(Address[]) f.hexToBytes().padLeft(0, 20);
            return v[0];
        }
        static if (is(To == Hash))
        {
            Hash[] v = cast(Hash[]) f.hexToBytes().padLeft(0, 32);
            return v[0];
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

auto padLeft(bytes data, ubyte b, ulong count)
{
    if (count > data.length)
    {
        auto pad = new ubyte[count - data.length];
        pad[] = b;
        return pad ~ data;
    }
    else
        return data;
}

auto padRight(bytes data, ubyte b, ulong count)
{
    if (count > data.length)
    {
        auto pad = new ubyte[count - data.length];
        pad[] = b;
        return data ~ pad;
    }
    else
        return data;
}

unittest
{
    import std;

    "0X TEST:".writeln;
    assert("0x123" == `123`.ox);
    char[4] t;
    t[] = 'a';
    assert(t.ox == "0xaaaa");
}
