module deth.util.rlp;

import std;

alias bytes = ubyte[];

bytes rlpEncode(bytes[] a)
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

bytes lenToRlp(ulong l, ubyte o)
{
    if (l < 56)
    {
        return [cast(ubyte)(l + o)];
    }
    else
    {
        bytes binL = l.nativeToBigEndian.cutBytes;
        ubyte lenOfLen = cast(ubyte)(binL.length + o + 55);
        return lenOfLen ~ binL;
    }
}

bytes cutBytes(bytes a) pure
{
    ulong i;
    for (i = 0; i < a.length; i++)
    {
        if (a[i] != 0)
        {
            break;
        }
    }
    return a[i .. $];
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
            ]).toHexString == "F84BB84563636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174636174617483646F67");
    assert(rlpEncode([cast(bytes) "cat", cast(bytes) ""]).toHexString == "C58363617480");
    bytes[] d = cast(bytes[])[[1], [2, 3, 4], [123, 255]];
    assert(rlpEncode(d).toHexString == "C80183020304827BFF");

}
