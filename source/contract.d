import std.json;
import std.stdio;
import std.array:replace, join;
import std.algorithm:canFind;
import rpcconnector;

enum STRINABLE = ["uint", "uint256", "string", "address"];
enum ERC20build= import("ERC20.json").parseJSON;

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
    return retVal[0..$-2];
}

class Contract(JSONValue compiledContract){
    private string address;
    private IEthRPC conn;
    static immutable string deployedBytecode = compiledContract["deployedBytecode"].str;
    mixin(allFunctions(compiledContract["abi"]));
    
    this(IEthRPC conn, string address = null){
        this.address = null;
    }
    // Send traansaction for deploy contract
    void deploy(string from = null){
        if(address is null){
            Transaction tr = {
                from: (from is null?conn.eth_accounts[0]:from),
                data: deployedBytecode,
                };
            auto trHash = conn.eth_sendTransaction(tr);
            address = conn
                .eth_getTransactionReceipt(trHash)["contractAddress"].str;

            if(address)
                throw new Exception("null address");
        }
        else
            throw new Exception("Contract alredy deployed");
    }
    private string callMethod(string signature, string params){
        
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

