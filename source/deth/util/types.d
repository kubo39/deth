module deth.util.types;

import std.algorithm:reverse;
import std.conv:to;
import std: toHexString;

struct FixedBytes(ulong size)
{
    static assert(size <= 32, "not supported size: " ~size);
    ubyte[size] value;
    string toString(){
        return (cast(ubyte[])value).toHexString.to!string;
    }   
}

