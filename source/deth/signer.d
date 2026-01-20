module deth.signer;

import std.digest : toHexString;
import std.logger;
import std.sumtype;

import deth.util.transaction;
import deth.util.types : Address, Hash, bytes, convTo, ox;

import keccak : keccak256;
import secp256k1 : Signature, secp256k1;

/// secp256k1 signer implementation.
class Signer
{
    /// Create a new secp256k1 signer from a private key.
    this(string privateKey) @safe
    {
        this(privateKey.convTo!Hash);
    }

    /// Ditto.
    this(Hash privateKey) @safe
    {
        keypair = new secp256k1(privateKey);
    }

    Address address() @safe pure nothrow const
    {
        return keypair.address;
    }

    /// Signs a transaction by stored in a private key.
    /// Params:
    ///   tx =  tx to sign
    /// Returns: rlp encoded signed transaction
    bytes signTransaction(Transaction tx) @safe
    {
        return tx.match!(
            (const LegacyTransaction legacyTx) => signTransaction(legacyTx),
            (const EIP2930Transaction eip2930Tx) => signTransaction(eip2930Tx),
            (const EIP1559Transaction eip1559Tx) => signTransaction(eip1559Tx),
        );
    }

    ///
    bytes signTransaction(const EIP2930Transaction tx) @trusted pure
    {
        bytes rlpTx = tx.serializeToRLP();
        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);

        // the secp256k1 sign function calls keccak256() internally.
        auto signature = keypair.sign(rlpTx);
        return tx.serializeToSignedRLP(signature);
    }

    ///
    bytes signTransaction(const EIP1559Transaction tx) @trusted pure
    {
        bytes rlpTx = tx.serializeToRLP();
        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);

        // the secp256k1 sign function calls keccak256() internally.
        auto signature = keypair.sign(rlpTx);
        return tx.serializeToSignedRLP(signature);
    }

    ///
    bytes signTransaction(const LegacyTransaction tx) @safe pure
    {
        bytes rlpTx = tx.serializeToRLP();
        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);

        // the secp256k1 sign function calls keccak256() internally.
        auto signature = keypair.sign(rlpTx);
        return tx.serializeToSignedRLP(signature);
    }

    /// Signs a message by stored in a private key.
    ///
    /// EIP-191: Signed Data Standard
    /// https://eips.ethereum.org/EIPS/eip-191
    ///
    /// hash = keccak256("\x19Ethereum Signed Message:\n" + len(message) + message)
    Signature signMessage(bytes message) @safe
    {
        return keypair.signHash(eip191HashMessage(message));
    }

    /// Ditto.
    Signature signMessage(string message) @trusted
    {
        return signMessage(cast(bytes) message);
    }

private:
    secp256k1 keypair;
}

/// Hash a message according to EIP-191.
Hash eip191HashMessage(const bytes message) @safe
{
    return keccak256(eip191PrefixedMessage(message));
}

private ubyte[] eip191PrefixedMessage(const bytes message) @safe
{
    import std.array : appender;
    import std.conv : to;

    auto prefix = cast(const(ubyte)[]) "\x19Ethereum Signed Message:\n";
    auto lenStr = cast(const(ubyte)[]) message.length.to!string;

    auto buffer = appender!(ubyte[]);
    buffer ~= prefix;
    buffer ~= lenStr;
    buffer ~= message;

    return buffer[];
}

@("eip-191: signs message")
unittest
{
    import secp256k1 : ecRecover;

    auto message = "Some data";
    auto signer = new Signer(
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    );
    const address = signer.address;
    auto sig = signer.signMessage(message);
    auto hashedMsg = eip191PrefixedMessage(cast(bytes) message);
    const recovered = ecRecover(sig, hashedMsg);
    assert(recovered == address);
}
