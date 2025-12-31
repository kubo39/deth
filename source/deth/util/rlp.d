module deth.util.rlp;

import std.array : replaceSlice;
import std.bitmanip : nativeToBigEndian, read;
import std.conv : to;
import std.digest : toHexString;
import std.exception : basicExceptionCtors;
import std.range : empty, popFrontExactly;

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
        assert(c.a.cutBytes == c.b.cutBytes);
        assert(c.a.cutBytes == c.a.cutBytes);
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
class InputIsNull : Exception
{
    mixin basicExceptionCtors;
}

///
class InputTooShort : Exception
{
    mixin basicExceptionCtors;
}

///
class InputTooLong : Exception
{
    mixin basicExceptionCtors;
}

///
class InvalidInput : Exception
{
    mixin basicExceptionCtors;
}

///
T rlpDecode(T)(const(ubyte)[] input) @trusted
{
    static if (is(T == bool))
    {
        if (input.length < 1)
            throw new InputTooShort("A bool must be one byte.");
        else if (input.length > 1)
            throw new InputTooLong("A bool must be one byte.");
        switch (input[0])
        {
        case 0x80:
            return false;
        case 0x1:
            return true;
        default:
            throw new InvalidInput("An invalid bool value.");
        }
    }
    else static if (is(T == ubyte) || is(T == ushort) || is(T == uint) || is(T == ulong))
    {
        const decodedHeader = decodeRlpHeader(input);
        assert(!decodedHeader.isList);
        assert(decodedHeader.payloadLen <= T.sizeof);

        if (decodedHeader.payloadLen == 0)
            return 0;

        const area = input[0 .. decodedHeader.payloadLen];
        input.popFrontExactly(decodedHeader.payloadLen);
        auto buffer = new ubyte[T.sizeof];
        buffer = buffer.replaceSlice(buffer[($ - area.length) .. $], area);
        T n = buffer.read!T;
        assert(buffer.empty);
        return n;
    }
    else static if (is(T == string))
    {
        const decodedHeader = decodeRlpHeader(input);
        assert(!decodedHeader.isList);
        return cast(T) input[0 ..  decodedHeader.payloadLen];
    }
    else static if (is(T == ubyte[]))
    {
        const decodedHeader = decodeRlpHeader(input);
        assert(decodedHeader.isList);
        return input[0 .. decodedHeader.payloadLen].dup;
    }
    else static if (is(T U == U[]))
    {
        static if (is(U == ubyte) || is(U == ushort) || is(U == uint) ||
            is(U == ulong) || is(U == string))
        {
            const decodedHeader = decodeRlpHeader(input);
            assert(decodedHeader.isList);

            if (input.length == 0)
                return [];

            T answer;

            // cannot pass ref for input directly,,
            size_t offset = input.length - decodedHeader.payloadLen;
            while (offset < input.length)
            {
                const(ubyte)[] tmp = input[offset .. $].dup;
                const decodedElemHeader = decodeRlpHeader(tmp);
                const newOffset = offset + decodedElemHeader.offset + decodedElemHeader.payloadLen;
                U elem = rlpDecode!U(input[offset .. newOffset]);
                answer ~= elem;
                offset = newOffset;
            }
            return answer;
        }
    }
    else static assert(false, "Unsupported type: " ~ T.stringof);
}

private struct DecodedHeader
{
    size_t offset;
    size_t payloadLen;
    bool isList;
}

private DecodedHeader decodeRlpHeader(ref const(ubyte)[] input) @trusted
{
    if (input.length == 0)
        throw new InputIsNull("RLP header size is zero.");

    bool isList = false;
    size_t offset;
    size_t payloadLen;

    const prefix = input[0];
    switch (prefix)
    {
    case 0: .. case 0x7F:
        payloadLen = 1;
        break;
    case 0x80: .. case 0xB7:
        input.read!ubyte;
        offset = 1;
        payloadLen = prefix - 0x80;
        break;
    case 0xB8: .. case 0xBF:
    case 0xF8: .. case 0xFF:
        input.read!ubyte;
        isList = prefix >= 0xF8;
        const code = isList ? 0xF7 : 0xB7;
        const lenOfPayloadLen = prefix - code;
        const payloadLenArea = input[0 .. lenOfPayloadLen];
        input.popFrontExactly(lenOfPayloadLen);

        ubyte[] buffer = [0, 0, 0, 0, 0, 0, 0, 0];
        // copy payloadLen to buffer.
        buffer = buffer.replaceSlice(buffer[($ - lenOfPayloadLen) .. $], payloadLenArea);
        payloadLen = cast(size_t) buffer.read!ulong;
        assert(buffer.empty);
        offset = 1 + lenOfPayloadLen;
        break;
    case 0xC0: .. case 0xF7:
        input.read!ubyte;
        offset = 1;
        isList = true;
        payloadLen = prefix - 0xC0;
        break;
    default:
        assert(false, "unreachable");
    }

    if (input.length < payloadLen)
        throw new InputTooShort("Too short payload was given.");

    return DecodedHeader(offset, payloadLen, isList);
}

@("rlp decode")
unittest
{
    import std.exception : assertThrown;

    // bool
    assert(rlpDecode!bool([0x80]) == false);
    assert(rlpDecode!bool([0x01]) == true);

    // ubyte
    assert(rlpDecode!ubyte([0x80]) == 0);
    assert(rlpDecode!ubyte([0x01]) == 1);

    // ulong
    assert(rlpDecode!ulong([0x80]) == 0);
    assert(rlpDecode!ulong([0x09]) == 9);
    assert(rlpDecode!ulong([0x82, 0x05, 0x05]) == 0x0505);

    // uint
    assert(rlpDecode!uint([0x09]) == 9);

    // string
    assert(rlpDecode!string([0x83, 'd', 'o', 'g']) == "dog");

    // ubyte[]
    assert(rlpDecode!(ubyte[])([0xC0]) == []);
    assert(rlpDecode!(ubyte[])([0xC3, 0x1, 0x2, 0x3]) == [0x1, 0x2, 0x3]);

    // ulong[]
    assert(rlpDecode!(ulong[])([0xC0]) == []);
    assert(rlpDecode!(ulong[])(
        [0xC8,
         0x83, 0xBB, 0xCC, 0xB5,
         0x83, 0xFF, 0xC0, 0xB5
        ]) == [0xBBCCB5, 0xFFC0B5]);

    // malformed RLP
    assertThrown!InputTooShort(rlpDecode!ubyte([0x82]));
    assertThrown!InputTooShort(rlpDecode!ulong([0x82]));
    assertThrown!InputTooShort(rlpDecode!string([0xC1]));
    assertThrown!InputTooShort(rlpDecode!string([0xD7]));
    assertThrown!InputTooShort(rlpDecode!(ubyte[])([0xC1]));
    assertThrown!InputTooShort(rlpDecode!(ubyte[])([0xD7]));
    assertThrown!InputTooShort(rlpDecode!(uint[])([0xC1]));
    assertThrown!InputTooShort(rlpDecode!(ulong[])([0xD7]));

    assertThrown!InputTooLong(rlpDecode!bool([0x80, 0x80]));
}
