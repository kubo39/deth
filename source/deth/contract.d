module deth.contract;

import std.json;
import std.bigint: BigInt;
import std.stdio;
import std.array: replace, join;
import std.string: indexOf;
import std.algorithm: canFind;
import deth.util.abi: toHex32String;
import deth.rpcconnector;

enum INTEGRAL = ["address"];

class Contract(string buildPath, string bin){
    enum build = import(buildPath).parseJSON;
    enum abi = build;
    private string address;
    private IEthRPC conn;

    static immutable string deployedBytecode = bin;
    
    
    this(IEthRPC conn){
        this.conn = conn;
        this.address = null;
    }

    debug pragma(msg, allFunctions(abi));
    mixin(allFunctions(abi));

    // Send traansaction for deploy contract
    void deploy(ARGS...)( ARGS argv){
        string from = null;
        if(address is null){
            Transaction tr;
            tr.from = (from is null?conn.eth_accounts[0]:from);
            tr.data = deployedBytecode~ toHex32String(argv);
            tr.gas = 6_721_975;
            auto trHash = conn.eth_sendTransaction(tr);
            address = conn
                .eth_getTransactionReceipt(trHash)["contractAddress"].str;

            if(address is null)
                throw new Exception("null address");
        }
        else
            throw new Exception("Contract alredy deployed");
    }
    override string toString(){
        return " Contract on "~address;
    }

    void callMethod(string signiture, ARGS...)(ARGS argv){
        string hash = conn.web3_sha3(signiture)[0..10]; //takin first 4 bytes
        string inputs = argv.toHex32String;
        Transaction tr;
        tr.data = hash ~ inputs;
        tr.from = conn.eth_accounts[0];
        tr.to = this.address;
        tr.writeln;
        conn.eth_call(tr, "latest".JSONValue).writeln;
    }
}


string parseFunction(JSONValue abi)
{
    return(
        q{
            void $funcName ( $inputs ) {
                $body
            }
        }.replace("$funcName", abi["name"].str)
         .replace("$inputs", abi["inputs"].getInputs)
         .replace("$body", q{callMethod!"$signature"($inputsValue);})
         .replace("$signature", abi.getSigniture)
         .replace("$inputsValue", abi["inputs"].getInputs(false))
   );
}

string allFunctions(JSONValue abi){
    string retVal = "";
    foreach (JSONValue func; abi.array){
        if(func["type"].str == "function"){
            retVal ~= func.parseFunction~ "\n\n";
        }
    }
    return retVal;
}

string getInputs(JSONValue params, bool typed = true){
    string[] inputs = [];
    foreach(param; params.array){
        try{

            if (param["type"].str.isIntegral){
                
                inputs ~= (typed?"BigInt ":"") ~ param["name"].str;
            } else if ("bool" == param["type"].str){
                inputs ~= (typed?"bool ":"") ~ param["name"].str;
            } else assert(0, "not supported tupe");
        }
        catch(Exception e){
            continue;
        }

    }
    return inputs.join(", ");
}

string getSigniture(JSONValue abi){
    JSONValue params = abi["inputs"];
    string[] types = [];
    foreach(param; params.array){
        types ~= param["type"].str;
    }
    return abi["name"].str ~ "("~ types.join(",") ~ ")";
}


bool isIntegral(string typeName){
    return 
        INTEGRAL.canFind(typeName) ||
        typeName.indexOf("int") >=0;
}
