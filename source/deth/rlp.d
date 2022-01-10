module deth.rlp;

alias bytes = ubyte[];

bytes rlpEncode(bytes[] a)
{
    bytes answer = [];
    answer ~= lenToRlp(a.length, 0xc0);
    foreach (item; a)
    {
        if (item.length == 1 && item.length < 0x80)
        {
            answer ~= item;
        }
        else
        {
            answer ~= lenToRlp(item.length, 0x80) ~ item;
        }
    }
    return answer;
}

bytes lenToRlp(ulong l, ubyte o)
{
    if (l < 56)
    {
        return [cast(ubyte)(l + o)];
    }
    else
    {
        ulong[1] t = [l];
        bytes binL = cast(bytes) t[];
        binL = binL.cutBytes;
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
}
