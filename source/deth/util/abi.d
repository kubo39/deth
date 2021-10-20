module deth.util.abi;

import std.traits:isInstanceOf, isIntegral,isBoolean, isStaticArray, 
       isDynamicArray, FieldNameTuple, isAggregateType;
import std: ElementType;
import std: to, writeln;
import std: BigInt, toHex, replace;
import std: map, join;

import deth.util.types: FixedBytes;

string toHex32String(ARGS...) (ARGS args){
    string value = "";
    string dynamicValue = "";

    ulong offset = args.length*32;
    
    foreach(arg; args){
        static if(isDynamicArray!(typeof(arg))){
            value ~= offset.toBytes32;
            string tmpDynamicValue = arg.toBytes32D(offset);
            offset += tmpDynamicValue.length/2;
            dynamicValue~=tmpDynamicValue;
        }
        else {
            value ~= arg.toBytes32;
        }
    }
    return value~dynamicValue; 
}

string toBytes32D(T)(T v, ulong offset){
    alias elemType = ElementType!T;

    string value = v.length.toBytes32;
    
    static if (isDynamicArray!elemType){
        static assert(0, "array of arrays is not avaliable now...");
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
    auto r = toHex32String(
            10, staticarray, b, "0x123".BigInt, [0x10,0x123,0x246], s
            );
    assert(r.length % 32*2 == 0);
    r.writeln;
    toHex32String([0x101,0x12345,0x246123], [0x420420420]).writeln;
}

