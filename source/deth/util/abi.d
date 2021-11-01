module deth.util.abi;

import std.traits:isInstanceOf, isIntegral,isBoolean, isStaticArray,
       isDynamicArray, FieldNameTuple, isAggregateType;
import std: ElementType;
import std: to, writeln, writef, text;
import std: BigInt, toHex, replace;
import std: map, join, fold;
import std: array, iota;
import deth.util.types: FixedBytes;

string encode(ARGS...) (ARGS args_){
    Pair res = {"", ""};
    auto args = args_.tuplelize;
    ulong offset = args.length*32;
    foreach(arg; args){
        res ~= arg.encodeUnit(offset);
    }
    return res.value ~ res.data; 
}

struct Pair{
    string value=""; // static encoded
    string data = ""; // dynamic encoded
    Pair opOpAssign(string op)(Pair a){
        static if(op == "~"){
            value~= a.value;
            data~= a.data;
            return this;
        }
    }
}

Pair encodeUnit(T)(T v, ref ulong offset){
    Pair result;
    result.data = "";
    static if(isBoolean!T || isIntegral!T){
        result.value = v.BigInt.toHex.replace("_", "").addNulls;
    } else static if (isStaticArray!T){
        result ~= v[].map!(e => e.encodeUnit(offset)).fold!(
                (a,b) => Pair(a.value~b.value, a.data ~ b.data));
    } else static if(isInstanceOf!(FixedBytes, T)){
        result.value = v.toString.addNulls(false);
    } else static if( is(T == BigInt) ) {
        result.value = v.toHex.replace("_", "").addNulls;
    } else static if (is( T == struct)) {
        result.value = "";
        static foreach(field; FieldNameTuple!T){
             Pair t = __traits(getMember, v, field).encodeUnit(offset);
             result.value ~= t.value;
             result.data ~= t.data;
        }
    } else static if (isDynamicArray!T){
        alias elemType = ElementType!T;
        result.value = offset.encodeUnit.value;
        offset += v[0].tuplelizeT.length*(v.length+1)*32;
        result.data ~= v.length.encodeUnit.value;
        Pair t;
        foreach(e; v){
            t ~= e.encodeUnit(offset);
        }
        result.data ~= t.value ~ t.data;
    }

    return result;
}
Pair encodeUnit(T)(T v){
    ulong DUMMY_OFFSET = 0;
    return encodeUnit(v, DUMMY_OFFSET);
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
    static if(is(T==BigInt)|| isInstanceOf!(FixedBytes, T)){
        return tuple(v);
    }else static if(isStaticArray!T){
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

void runTest(ARGS...)(ARGS argv){
    auto encoded = encode(argv);
    auto arr = encoded.split32;
    writeln(ARGS.stringof, argv);
    arr.length.iota.formatWriteln;
    arr.formatWriteln;
    arr.map!"a/32".formatWriteln;
    encoded.writeln;
    writeln;
}

unittest{
    runTest(0x122);
    runTest([1,2,3]);
    runTest([[10, 20, 30], [40,50,60]],[90,100]);
}
