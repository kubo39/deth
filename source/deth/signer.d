module deth.signer;

import std.digest : toHexString;
import std.logger;
import std.sumtype;

import deth.util.transaction;
import deth.util.types : Address, Hash, bytes, convTo, ox;

import keccak : keccak256;
import secp256k1 : secp256k1;

class Signer
{
    this(string privateKey) @safe
    {
        this(privateKey.convTo!Hash);
    }

    this(Hash privateKey) @safe
    {
        keypair = new secp256k1(privateKey);
    }

    Address address() @safe pure nothrow
    {
        return keypair.address;
    }

    /// Signs transaction by stored in wallet key
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

private:
    secp256k1 keypair;
}
