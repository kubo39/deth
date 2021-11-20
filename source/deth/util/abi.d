module deth.util.abi;

import std.traits:isInstanceOf, isIntegral,isBoolean, isStaticArray,
       isDynamicArray, FieldNameTuple, isAggregateType, Unconst;
import std: ElementType;
import std: to, writeln, writef, text;
import std: BigInt, toHex, replace;
import std: map, join, fold;
import std: array, iota;
import deth.util.types: FixedBytes;

enum OFFSET_PREFIX = '\0';

string encode(ARGS...) (ARGS args_){
    EncodingResult res;
    auto args = args_.tuplelize;
    ulong offset = args.length * 32;
    foreach(arg; args){
        auto t = arg.encodeUnit;
        if(t.value == ""){
            t.value ~= offset.encodeUnit.value;
        }
        res ~= t;
        offset += t.data.length/2;
        
    }
    auto encoded = res.value ~ res.data; 
    return encoded; 
}

struct EncodingResult{
    string value=""; // static encoded
    string data = ""; // dynamic encoded

    EncodingResult opOpAssign(string op)(EncodingResult a){
        static if(op == "~"){
            value~= a.value;
            data~= a.data;
            return this;
        }
    }
}

EncodingResult encodeUnit(T)(T v){
    EncodingResult result;
    static if(isBoolean!T || isIntegral!T){
        result.value = v.BigInt.toHex.replace("_", "").padByNulls;
    } else static if (isStaticArray!T){
        result ~= v[].map!(e => e.encodeUnit).fold!(
                (a,b) => EncodingResult(a.value~b.value, a.data ~ b.data));
    } else static if(isInstanceOf!(FixedBytes, T)){
        result.value = v.toString.padByNulls(false);
    } else static if( is(T == BigInt) ) {
        result.value = v.toHex.replace("_", "").padByNulls;
    } else static if (is( T == struct)) {
        static foreach(field; FieldNameTuple!T){
            result ~= __traits(getMember, v, field).encodeUnit;
        }
    } else static if (isDynamicArray!T){
        alias E = ElementType!T;
        result.data ~= v.length.encodeUnit.value;
        EncodingResult arr;
        auto offset = v.length * 32;
        foreach(e; v){
            auto t = e.encodeUnit;
            static if(isDynamicArray!E){
                // element is dynamic array
                t.value ~= offset.encodeUnit.value;
            }
            
            arr ~= t;
            offset += t.data.length/2;
        }
        result.data ~= arr.value.padByNulls(false) ~ arr.data;
    } else static if(is(Unconst!T == char ) || is(Unconst!T == ubyte)){
        result.value = (cast(ubyte)v).to!string(16);
    }
    else static assert(0, "Type no supported: " ~ T.stringof);
    return result;
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

string padByNulls(string data, bool left = true){
    static immutable registerSize = 64;
    if(data.length % registerSize == 0 ){
        return data;
    }
    auto pad = new char[registerSize - data.length%registerSize];
    pad[] = '0';
    if (left){
        data = cast(string) pad ~ data;
    }
    else{
        data ~= cast(string )pad;
    }
    return data;
}
version (unittest){
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
        encoded.length.writeln("size");
        writeln;
    }
}

unittest{
    runTest(0x122);
    runTest([10], [20], [30]);
    runTest([[10, 20], [30]], [[1], [2], [3]]);
    runTest([1,2,3], [4,5,6], [8,9]);
    runTest([[10, 20, 30], [40,50,60]],[90,100]);
    runTest("Hello, world!");
}