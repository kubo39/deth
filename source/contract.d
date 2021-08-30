import std.json;
import std.stdio;
import std.array:replace, join;
import std.algorithm:canFind;
import rpcconnector;

enum STRINABLE = ["uint", "uint256", "string", "address"];

class Contract(string buildPath, string bin){
    enum build = import(buildPath).parseJSON;
    enum abi = build;
    private string address;
    private IEthRPC conn;

    static immutable string deployedBytecode = bin;
    
    
    this(IEthRPC conn, string address = null){
        this.conn = conn;
        this.address = null;
    }

    mixin(allFunctions(abi));

    // Send traansaction for deploy contract
    void deploy(string from = null){
        if(address is null){
            Transaction tr;
            tr.from = (from is null?conn.eth_accounts[0]:from);
            tr.data = deployedBytecode;
            auto trHash = conn.eth_sendTransaction(tr);
            address = conn
                .eth_getTransactionReceipt(trHash)["contractAddress"].str;

            if(address)
                throw new Exception("null address");
        }
        else
            throw new Exception("Contract alredy deployed");
    }
}

string toBytes32(T)(T v){
    enum SIZE = T.sizeof;
    ubyte* ptr = cast(ubyte*)v.ptr;
    string value = "";
    
    for(int i = 0; i<SIZE; i++){
        value~=ptr[SIZE-i-1].to!(string,16);
    }

    return value;
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
unittest {
    import std:writeln;
    import(ERC20build).parseJSON["abi"].allFunctions.writeln;
}
