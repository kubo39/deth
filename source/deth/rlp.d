module deth.rlp;

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
        bytes binL = l.nativeToBigEndian[].cutBytes;
        ubyte lenOfLen = cast(ubyte)(binL.length + o + 55);
        return lenOfLen ~ binL;
    }
}

bytes cutBytes(bytes a)
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

unittest
{
    bytes a = [1, 2, 3];
    bytes b = [0, 0, 1, 2, 3];
    assert(a.cutBytes == b.cutBytes);
    assert(a.cutBytes == a.cutBytes);
    ubyte[8] t = 1L.nativeToBigEndian;
    writeln(cast(bytes) t[]);
}

unittest
{
    rlpEncode([cast(bytes) "cat", cast(bytes) "dog"]).map!q{a.to!string(16)}.join.writeln;
    rlpEncode([
        cast(bytes) "ccatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatcatat",
        cast(bytes) "dog"
    ]).map!"a.to!string(16)".join.writeln;
}
