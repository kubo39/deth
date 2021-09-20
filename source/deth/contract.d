module deth.contract;

import std.json;
import std.stdio;
import std.array:replace, join;
import std.algorithm:canFind;
import deth.util.evmcoder:toHex32String;
import deth.rpcconnector;

enum STRINABLE = ["uint", "uint256", "string", "address"];

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
}


string parseFunction(JSONValue abi)
{
    return(
        q{
            void $funcName ( $inputs ) {
                
            }
        }.replace("$funcName", abi["name"].str)
         .replace("$inputs", abi["inputs"].getInputs)
    );
}

string allFunctions(JSONValue abi){
    string retVal = "";
    foreach (JSONValue func; abi.array){
        try{
            if(func["type"].str == "function"){
                retVal ~= func.parseFunction~ "\n\n";
            }
        }
        catch(Exception e){
            continue;
        }
    }
    return retVal;
}

string getInputs(JSONValue params){
    string retVal = "";
    foreach(param; params.array){
        try{
            if (STRINABLE.canFind(param["type"].str)){
                retVal ~= "string " ~ param["name"].str;
            }
            if ("bool" == param["type"].str){
                retVal ~= "string " ~ param["name"].str;
            }
            retVal ~= ", ";
        }
        catch(Exception e){
            continue;
        }

    }
    if(retVal.length)
        return retVal[0..$-2];
    else return "";
}

