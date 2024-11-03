# Deth

D library for interacting to contracts

## Dependencies

- [libsecp256k1](https://github.com/bitcoin-core/secp256k1/)

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

