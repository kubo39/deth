/// PrivateKeys manipulator
module deth.wallet;

import std.bigint;
import std.exception : enforce;
import std.logger;
import std.sumtype;

import deth.util : Address, Hash, bytes, convTo, Transaction, ox;
import deth.util.transaction;

import secp256k1 : secp256k1;

/// struct to store several private keys in a single wallet
struct Wallet
{
    private secp256k1[Address] addrs;

    this(ARGS...)(ARGS argv) @safe
    {
        foreach (v; argv)
            addPrivateKey(v);
    }
    /// method to add a private key
    /// 
    /// Params:
    ///   key = private key stored in ubyte[32], string, ubyte[]
    void addPrivateKey(T)(T key) @safe
    {
        static if (is(T : Hash))
            auto c = new secp256k1(key);
        else static if (is(T : string))
            auto c = new secp256k1(key.convTo!Hash);
        else static if (is(T : bytes))
            auto c = new secp256k1(key[0 .. 32]);
        else
            static assert(0, T.stringof ~ " not supported");

        tracef("Added private key for %s", c.address.convTo!string);
        addrs[c.address] = c;
    }

    /// rms address from wallet
    /// Params:
    ///   addr = address to remove
    void remove(Address[] addr...) @safe
    {
        foreach (a; addr)
            addrs.remove(a);
    }

    /// Returns: list address stored in wallet;
    @property Address[] addresses() const pure @safe nothrow
    {
        return addrs.keys;
    }

    /// Signs transaction by some stored in wallet key
    /// Params:
    ///   tx =  tx to sign
    ///   signer = address which key will be used to sign if tx hasn't store from field
    /// Returns: rlp encoded signed transaction
    bytes signTransaction(const Transaction tx, Address signer = Address.init) @safe pure
    {
        return tx.match!(
            (const LegacyTransaction legacyTx) => signTransaction(legacyTx, signer),
            (const EIP2930Transaction eip2930Tx) => signTransaction(eip2930Tx, signer),
            (const EIP1559Transaction eip1559Tx) => signTransaction(eip1559Tx, signer),
        );
    }

    ///
    bytes signTransaction(const EIP2930Transaction tx, Address signer = Address.init) @trusted pure
    {
        import keccak : keccak256;
        import deth.util.types;

        if (!tx.from.isNull)
        {
            signer = tx.from.get;
            debug tracef("address is choosed from tx field %s", signer.convTo!string.ox);
        }
        else
            debug tracef("address is choosed from optional argument %s", signer.convTo!string.ox);
        enforce(signer in addrs, "Address %s not found", signer.convTo!string.ox);

        auto c = addrs[signer];

        bytes rlpTx = tx.serializeToRLP();
        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);

        // the secp256k1 sign function calls keccak256() internally.
        auto signature = c.sign(rlpTx);
        return tx.serializeToSignedRLP(signature);
    }

    ///
    bytes signTransaction(const EIP1559Transaction tx, Address signer = Address.init) @trusted pure
    {
        import keccak : keccak256;
        import deth.util.types;

        if (!tx.from.isNull)
        {
            signer = tx.from.get;
            debug tracef("address is choosed from tx field %s", signer.convTo!string.ox);
        }
        else
            debug tracef("address is choosed from optional argument %s", signer.convTo!string.ox);
        enforce(signer in addrs, "Address %s not found", signer.convTo!string.ox);

        auto c = addrs[signer];

        bytes rlpTx = tx.serializeToRLP();
        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);

        // the secp256k1 sign function calls keccak256() internally.
        auto signature = c.sign(rlpTx);
        return tx.serializeToSignedRLP(signature);
    }

    ///
    bytes signTransaction(const LegacyTransaction tx, Address signer = Address.init) @safe pure
    {
        import keccak : keccak256;
        import deth.util.types;

        if (!tx.from.isNull)
        {
            signer = tx.from.get;
            debug tracef("address is choosed from tx field %s", signer.convTo!string.ox);
        }
        else
            debug tracef("address is choosed from optional argument %s", signer.convTo!string.ox);
        enforce(signer in addrs, "Address %s not found", signer.convTo!string.ox);

        auto c = addrs[signer];
        bytes rlpTx = tx.serializeToRLP();
        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);

        // the secp256k1 sign function calls keccak256() internally.
        auto signature = c.sign(rlpTx);
        return tx.serializeToSignedRLP(signature);
    }
}
