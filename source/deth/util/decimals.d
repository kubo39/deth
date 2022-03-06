module deth.util.decimals;

import std.string : format;

auto toWei(ulong decimals, T)(T value)
{
    import std.bigint : BigInt;

    return value.BigInt * (10.BigInt ^^ decimals);
}

mixin template Converter(ulong decimal, string name)
{
    mixin(q{
        auto %s(T)(T v)
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

    import std.stdio;
    import std.bigint : BigInt;

    assert(10.gwei == "10_000_000_000".BigInt);
    assert(10.ether == "10_000_000_000_000_000_000".BigInt);
}
