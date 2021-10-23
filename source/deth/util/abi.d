module deth.util.abi;

import std.traits:isInstanceOf, isIntegral,isBoolean, isStaticArray,
       isDynamicArray, FieldNameTuple, isAggregateType;
import std: ElementType;
import std: to, writeln, writef, text;
import std: BigInt, toHex, replace;
import std: map, join;
import std: array, iota;
import deth.util.types: FixedBytes;

string encode(ARGS...) (ARGS args){
    string value = "";
    string dynamicValue = "";
    args.writeln;
    ulong offset = args.length*32;
    foreach(arg; args){
        static if(isDynamicArray!(typeof(arg))){
            value ~= offset.toBytes32;
            dynamicValue ~= arg.toBytes32D(offset);
        }
        else {
            value ~= arg.toBytes32;
        }
    }
    return value ~ dynamicValue;
}

string toBytes32D(T)(T v, ref ulong offset){
    alias elemType = ElementType!T;

    string value = v.length.toBytes32;
    offset += (v.length+1)*32;

    static if (isDynamicArray!elemType){
        string dynamicValue = "";
        foreach(e; v){
            value ~= offset.toBytes32;
            dynamicValue ~= e.toBytes32D(offset);
        }
        value ~= dynamicValue;
    }
    else {
        foreach(e; v){
            value ~= e.toBytes32;
        }
    }
    return value;

}

string toBytes32(T)(T v){
    static if(isBoolean!T || isIntegral!T){
        enum SIZE = T.sizeof;
        ubyte* ptr = cast(ubyte*) &v;
        string value = "";

        for(int i = 0; i<SIZE; i++){
            string b = ptr[SIZE-i-1].to!string(16);
            value~= (b.length==2?b:"0"~b);
        }

        return value.addNulls;
    }
    else static if (isStaticArray!T){
        return v[].map!toBytes32.join;
    }
    else static if(isInstanceOf!(FixedBytes, T)){
        return v.toString.addNulls(false);
    }
    else static if(is(T == BigInt)){
        return v.toHex.replace("_", "").addNulls;
    }
    else static if(is(T == struct)){
        string t = "";
        static foreach(field; FieldNameTuple!T){
            t ~= __traits(getMember, v, field).toBytes32;
        }
        return t;
    }
    else static assert(0, "type");
}

auto tuplelize(ARGS...)(ARGS argv){
    auto code(){ 
        string[] res;  
        foreach (i; 0..argv.length){
            res ~= text(`tuplelizeT(argv[`,i,`])`);
        }
        return res.join("~ ");
    }
    mixin(`return `~ code~ `;`);
}

auto tuplelizeT(T)(T v){
    import std: tuple;
    static if(isStaticArray!T){
        mixin(q{
                return tuple(}
                        ~ v.length.iota.map!q{text(`v[`, a, `]`)}.join(`, `)
                        ~ `);`
             );
    }else static if (is(T == struct)){
        auto code(){ 
            string[] res;  
            foreach (field; FieldNameTuple!T){
                res ~= `tuplelizeT(v.`~field~')';
            }
            return res.join("~ ");
        }
        mixin(`return `~ code~ `;`);  
    }
    else return tuple(v);
}

string addNulls(string t, bool front = true)
in(t.length<=64)
{
    string nulls= "";
    foreach(_; 0..64 - t.length){
        nulls ~= "0";
    }
    if(front){
        return nulls~t;
    }
    else {
        return t~nulls;
    }
}

unittest{
    "to Hex 32 test".writeln;
    FixedBytes!10 b;
    b.value[0..3] = cast(ubyte[])"abc";
    int[2] staticarray= [1, 2 ];
    struct S {
        int a;
        int b;
    }
    S s = {1000,0xabc};
    auto r = encode(
            10, staticarray, b, "0x123".BigInt, [0x10,0x123,0x246], s
            );
    assert(r.length % 32*2 == 0);
    r.writeln;
    encode([0x101,0x12345,0x246123], [0x420420420]).writeln;
}

BigInt[] split32(string a){
    auto sliceCount = a.length/64;
    string[] v = [];
    v.reserve(sliceCount);
    foreach(i; 0..sliceCount){
        v ~= a[i*64..(i+1)*64];
    }
    return v
        .map!`"0x"~a`
        .map!BigInt
        .array;
}

auto formatWriteln(T)(T a){
    foreach(e;a){
        writef("%4d ", e);
    }
    writeln;
}
unittest{
    int[][][] a = [[[1, 2, 3], [4, 5], [6]], [[7,8],[9]]];
    auto encoded = encode(a, a );
    auto arr = encoded.split32;
    arr.length.iota.formatWriteln;
    writeln;
    arr.formatWriteln;
    arr.map!"a/32".formatWriteln;
    encoded.writeln;
}

unittest {
    struct Wallet{
        int[2] curr = [0x1, 0x2];
    }

    struct Person{
        int age = 123;
        Wallet w;
    }

    Person b;
    tuplelize(b, "1123", [1,2,3,4,5]).writeln;
}
