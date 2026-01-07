module deth.util.rlp;

import std.array : appender, replaceSlice;
import std.bitmanip : nativeToBigEndian, read;
import std.conv : to;
import std.digest : toHexString;
import std.exception : basicExceptionCtors;
import std.range : empty, popFrontExactly;

alias bytes = ubyte[];

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
