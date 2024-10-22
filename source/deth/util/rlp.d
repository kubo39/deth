module deth.util.rlp;

import std.array : replaceSlice;
import std.bitmanip : nativeToBigEndian, read;
import std.conv : to;
import std.digest : toHexString;
import std.range : empty;

alias bytes = ubyte[];

/// 
/// Params:
///   a = massive of bytes; could be data or rlp encoded bytes
/// Returns: rlp encoded bytes
bytes rlpEncode(const bytes[] a) pure nothrow @safe
{
    bytes answer = [];
    foreach (item; a)
    {
        if (item.length == 1 && item[0] < 0x80)
        {
            answer ~= item;
        }
        else
        {
            answer ~= lenToRlp(item.length, 0x80) ~ item;
        }
    }
    return lenToRlp(answer.length, 0xc0) ~ answer;
}

private bytes lenToRlp(ulong l, ubyte o) pure nothrow @safe
{
    if (l < 56)
    {
        return [cast(ubyte)(l + o)];
    }
    else
    {
        bytes binL = l.nativeToBigEndian.dup.cutBytes;
        ubyte lenOfLen = cast(ubyte)(binL.length + o + 55);
        return lenOfLen ~ binL;
    }
}

bytes cutBytes(const bytes a) pure nothrow @safe
{
    ulong i;
    for (i = 0; i < a.length; i++)
    {
        if (a[i] != 0)
        {
            break;
        }
    }
    return a[i .. $].dup;
}

@("cutting null bytes")
unittest
{
    struct Case
    {
        bytes a, b;
    }

    import deth.util.types : convTo;

    Case[] cases = [
        Case([1, 2, 3], [0, 0, 1, 2, 3]),
        Case([1, 1, 0, 0, 1, 2, 3], [0, 0, 1, 1, 0, 0, 1, 2, 3]),
        Case([45, 128, 0, 0, 1, 2, 3], [0, 0, 45, 128, 0, 0, 1, 2, 3]),
        Case([1, 0], 256.convTo!bytes),
        Case([1, 0, 0, 0, 0], (1L << 32).convTo!bytes),
    ];
    foreach (c; cases)
    {
        assert(c.a.dup.cutBytes == c.b.dup.cutBytes);
        assert(c.a.dup.cutBytes == c.a.dup.cutBytes);
    }
}

@("rlp encode")
unittest
{
    assert(rlpEncode([
            cast(bytes) "cat", cast(bytes) "dog", cast(bytes) "dogg\0y",
            cast(bytes) "man"
        ]).toHexString == "D38363617483646F6786646F67670079836D616E");
    assert(rlpEncode([
            cast(bytes) "ccatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatat",
            cast(bytes) "dog"
        ]).toHexString == "F84BB845636361746361746361746361746361746361746361746361746361746"
        ~ "36174636174636174636174636174636174636174636174636174636174636174636174636174617483646F67");
    assert(rlpEncode([cast(bytes) "cat", cast(bytes) ""]).toHexString == "C58363617480");
    bytes[] d = cast(bytes[])[[1], [2, 3, 4], [123, 255]];
    assert(rlpEncode(d).toHexString == "C80183020304827BFF");
}

///
T rlpDecode(T)(const bytes input) @trusted
{
    static if (is(T == bool))
    {
        if (input.length != 1)
            throw new Exception("too short input");
        switch (input[0])
        {
        case 0x80:
            return false;
        case 0x1:
            return true;
        default:
            throw new Exception("invalid bool value");
        }
    }
    else static if (is(T == ubyte))
    {
        if (input.length != 1)
            throw new Exception("invalid ubyte value");
        return input[0] & 0x7F;
    }
    else static if (is(T == ushort) || is(T == uint) || is(T == ulong))
    {
        DecodedHeader decodedHeader = decodeRlpHeader(input[]);
        assert(!decodedHeader.isList);
        assert(decodedHeader.payloadLen <= T.sizeof);

        if (decodedHeader.payloadLen == 0)
            return 0;

        const area = input[decodedHeader.offset .. decodedHeader.offset + decodedHeader.payloadLen];
        auto buffer = new ubyte[T.sizeof];
        buffer = buffer.replaceSlice(buffer[($ - area.length) .. $], area);
        T n = buffer.read!T;
        assert(buffer.empty);
        return n;
    }
    else static if (is(T == string))
    {
        DecodedHeader decodedHeader = decodeRlpHeader(input[]);
        assert(!decodedHeader.isList);
        return cast(string) input[decodedHeader.offset .. decodedHeader.offset + decodedHeader.payloadLen];
    }
    else static if (is(T U == U[]))
    {
        DecodedHeader decodedHeader = decodeRlpHeader(input[]);
        assert(decodedHeader.isList);

        if (decodedHeader.payloadLen == 0)
            return [];

        U elem = rlpDecode!U(input[decodedHeader.offset .. decodedHeader.offset + decodedHeader.payloadLen]);
        return [elem];
    }
    else static assert(false, "Unsupported type: " ~ T.stringof);
}

struct DecodedHeader
{
    size_t offset;
    size_t payloadLen;
    bool isList;
}

private DecodedHeader decodeRlpHeader(const bytes input) @trusted
{
    if (input.length == 0)
    {
        throw new Exception("input is null");
    }

    bool isList = false;
    size_t offset;
    size_t payloadLen;

    ubyte prefix = input[0];
    switch (prefix)
    {
    case 0: .. case 0x7F:
        payloadLen = 1;
        break;
    case 0x80: .. case 0xB7:
        offset = 1;
        payloadLen = prefix - 0x80;
        break;
    case 0xB8: .. case 0xBF:
        const lenOfStrLen = prefix - 0xB7;
        const strLenArea = input[2 .. 2 + lenOfStrLen];

        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0];
        // copy strLen to buffer.
        buffer = buffer.replaceSlice(buffer[($ - lenOfStrLen) .. $], strLenArea);
        const strLen = buffer.read!ulong;
        assert(buffer.empty);

        offset = 1 + lenOfStrLen;
        payloadLen = strLen.to!size_t;
        break;
    case 0xC0: .. case 0xF7:
        isList = true;
        payloadLen = prefix - 0xC0;
        break;
    case 0xF8: .. case 0xFF:
        isList = true;
        break;
    default:
        assert(false, "unreachable");
    }
    return DecodedHeader(
        offset: offset,
        payloadLen: payloadLen,
        isList: isList
    );
}

@("rlp decode")
unittest
{
    // bool
    assert(rlpDecode!bool([0x80]) == false);
    assert(rlpDecode!bool([0x01]) == true);

    // ubyte
    assert(rlpDecode!ubyte([0x80]) == 0);
    assert(rlpDecode!ubyte([0x01]) == 1);

    // ulong
    assert(rlpDecode!ulong([0x80]) == 0);
    assert(rlpDecode!ulong([0x09]) == 9);

    // uint
    assert(rlpDecode!uint([0x09]) == 9);

    // string
    assert(rlpDecode!string([0x83, 'd', 'o', 'g']) == "dog");

    // ulong[]
    assert(rlpDecode!(ulong[])([0xC0]) == []);
}
