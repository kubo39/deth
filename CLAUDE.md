# Deth Development Guide for AI Agents

## Project Overview

Deth is a D language Ethereum utility library and Web3 client implementation. Unlike execution layer clients (e.g., reth, geth), deth focuses on:

- **RPC Client**: JSON-RPC interface to interact with Ethereum nodes
- **Transaction Handling**: Building, signing, and sending transactions (Legacy, EIP-2930, EIP-1559)
- **ABI Encoding/Decoding**: Solidity ABI specification compliance
- **Contract Interaction**: Type-safe contract calls via compile-time code generation
- **Cryptographic Signing**: EIP-191 message signing, transaction signing with secp256k1

## Architecture Overview

### Core Modules

| Module | Purpose |
|--------|---------|
| `rpcconnector` | JSON-RPC client wrapping tynukrpc, provides typed Ethereum RPC methods |
| `signer` | Transaction and message signing using secp256k1 |
| `wallet` | Multi-signer management |
| `contract` | Compile-time ABI parsing and contract interaction |
| `util/transaction` | Transaction types (Legacy, EIP-2930, EIP-1559) and SumType wrappers |
| `util/abi` | ABI encoding/decoding for Solidity types |
| `util/types` | Primitive types (Address, Hash, bytes) and conversions |
| `util/decimals` | Wei/Gwei/Ether unit conversions |

### Design Principles

1. **Type Safety**: Use D's compile-time features (templates, mixins) for type-safe APIs
2. **SumType for Variants**: Transaction variants use `std.sumtype.SumType` for exhaustive matching
3. **Nullable for Optional Fields**: Transaction fields use `std.typecons.Nullable`

## Development Workflow

### Build and Test Commands

```bash
# Build
dub build

# Run unit tests (no anvil required)
dub test

# Run integration tests (requires anvil running on localhost:8545)
dub test --d-version=IntegrationTest

# Run full CI tests (starts anvil automatically)
sh ci-test.sh

# Run specific example
dub run deth:transfer
dub run deth:devtest
dub run deth:deploybytecode
```

### Testing Strategy

Tests are separated into two categories:

1. **Unit Tests** (`dub test`): No external dependencies required
   - In-file `unittest` blocks for pure functions (encoding, type conversion, etc.)
   - Mock RPC tests using `MockRpcClient` for RPC method testing without network

2. **Integration Tests** (`dub test --d-version=IntegrationTest`): Requires anvil
   - Tests that connect to actual RPC server (anvil on `localhost:8545`)
   - Wrapped in `version (IntegrationTest)` blocks

For full test coverage, use `sh ci-test.sh` which runs both unit and integration tests.

### Common Contribution Patterns

| Pattern | Description |
|---------|-------------|
| Adding RPC method | Add to `IEthRPC` interface, implement wrapper in `RPCConnector` |
| New transaction type | Add struct, update `Transaction` SumType, add helper functions |
| ABI type support | Extend `encode`/`decode` templates in `util/abi.d` |
| Signer feature | Implement in `Signer` class, consider trait abstraction |

## Code Standards

### Transaction Type Handling

Always use `Transaction` (SumType) for public APIs:

```d
// Good: Accept Transaction SumType
Hash sendRawTransaction(const Transaction tx) @safe;

// Avoid: Concrete type overloads (removed in recent refactor)
// Hash sendRawTransaction(const LegacyTransaction tx) @safe;
```

When calling methods that expect `Transaction`:

```d
LegacyTransaction tx = { to: recipient, value: amount };
conn.sendTransaction(Transaction(tx));  // Wrap with Transaction()
```

### Attributes

Prefer `@safe` and `pure` where possible:

```d
// Good
bytes serializeToRLP(const Transaction tx) pure @safe;

// Use @trusted only when wrapping unsafe operations
bytes signTransaction(const Transaction tx) @trusted;
```

### Error Handling

Currently uses exceptions via `std.exception.enforce`.

```d
enforce(!from.isNull, "from is required");
```

## CI Requirements

Before submitting PR:

1. `dub build` - Compiles without errors
2. `dub test` - All unit tests pass (no anvil required)
3. `sh ci-test.sh` - Full test suite including integration tests

## Project Structure

```
source/deth/
├── package.d           # Public exports
├── rpcconnector.d      # RPC client
├── signer.d            # Transaction/message signing
├── wallet.d            # Multi-signer wallet
├── contract.d          # Contract ABI interaction
└── util/
    ├── package.d       # Util exports
    ├── abi.d           # ABI encoding/decoding
    ├── decimals.d      # Unit conversions
    ├── transaction.d   # Transaction types
    └── types.d         # Primitive types

examples/
├── devtest/            # Contract interaction example
├── transfer/           # Simple transfer example
└── deploybytecode/     # Contract deployment example
```

## Quick Reference

```bash
# Build
dub build

# Run unit tests (no anvil required)
dub test

# Run integration tests (requires anvil on localhost:8545)
dub test --d-version=IntegrationTest

# Run full CI (starts anvil, runs tests + examples)
sh ci-test.sh

# Start anvil manually for development
anvil --balance 1000000

# Run examples (requires anvil)
dub run deth:transfer
dub run deth:devtest
dub run deth:deploybytecode
```
