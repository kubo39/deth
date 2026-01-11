module deth.util.decimals;

import std.bigint : BigInt;

auto toWei(ulong decimals, T)(T value) pure nothrow @safe
{
    return value.BigInt * (10.BigInt ^^ decimals);
}

mixin template Converter(ulong decimal, string name)
{
    private import std.string : format;
    mixin(q{
        pragma(inline, true) auto %s(T)(T v) pure nothrow @safe
        {
            return v.toWei!%d;
        }
   }.format(name, decimal));
}

mixin Converter!(18, "ether");
mixin Converter!(9, "gwei");
mixin Converter!(0, "wei");

@("decimals conv")
unittest
{
    assert(10.gwei == "10_000_000_000".BigInt);
    assert(10.ether == "10_000_000_000_000_000_000".BigInt);
}
