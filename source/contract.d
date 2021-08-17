import std.json;
import std.stdio;
import std.array:replace, join;
import std.algorithm:canFind;

enum STRINABLE = ["uint", "uint256", "string", "address"];
enum ERC20abi = import("abis/ERC20.json").parseJSON;

string parseFunction(JSONValue abi)
{
    return(
        q{
            void $funcName ( $inputs ) {
                " $funcName called".writeln;
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

struct Contract(JSONValue abi){
    mixin(allFunctions(abi));
}
