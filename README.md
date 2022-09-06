# Deth

D library for interacting to contracts

## Dependencies
- [libsecp256k1](https://github.com/bitcoin-core/secp256k1/)

## TODO
 - [ ] ddoc
 - [x] add attributes const, pure, etc - 0.0.8-alpha
 - [ ] Artifacts and ContractABI improvments - 0.0.9-alpha
 - [ ] improvements for sending tx(waiter, nonce increment) - 0.0.10-alpha
 - [ ] fix decode(add more types) - 0.0.11-alpha
 - [ ] libriry linking - 0.0.12-alpha
 - [ ] ... 
 - [ ] Test Template for testing contracts - 1.0.0-rc000
 - [ ] ...
 - [ ] Template for testing contracts - 1.0.0

## Example
```d
import std.stdio;

import deth;

static immutable TokenABI = ContractABI.load!"build/DFT.abi";
alias Token = Contract!TokenABI;

void main()
{
    auto conn = new RPCConnector("http://localhost:8545");
    Token.deployedBytecode = import("build/DFT.bin").convTo!bytes;
    /// don't paste pk in code
    conn.wallet.addPrivateKey("beb75b08049e9316d1375999c7d968f3c23fdf606b296fcdfc9a41cdd7e7347c");

    auto token = new Token(conn, "0x95710DC9F373E58df72692C3459D93Cd1BC2C6C5".convTo!Address);
    token.transfer("0xdddddddd0d0d0d0d0d0d0ddddddddd".convTo!Address, 0xd.wei).send();
}
```

