/// PrivateKeys manipulator
module deth.wallet;

import std.experimental.logger;
import std.exception : enforce;
import secp256k1 : secp256k1;
import deth.util : Address, Hash, bytes, convTo, Transaction, ox;
import deth.util.rlp : rlpEncode, cutBytes;
import deth.util.transaction : TransactionType;

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
        bytes[] serialized = tx.serialize;
        bytes rlpTx = serialized.rlpEncode;
        if (!tx.type.isNull && tx.type.get != TransactionType.LEGACY)
        {
            rlpTx = tx.type.get ~ rlpTx;
        }
        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);
        // the secp256k1 sign function calls keccak256() internally.
        auto signature = c.sign(rlpTx);
        bytes rawTx;
        if (tx.chainid.isNull)
        {
            ulong v = 27 + signature.recid;
            rawTx = rlpEncode(
                    serialized ~ v.convTo!bytes.cutBytes
                    ~ signature.r.cutBytes ~ signature.s.cutBytes);
        }
        else
        {
            /// eip 155 signing
            ulong v = signature.recid + tx.chainid.get * 2 + 35;
            size_t lastIndex = serialized.length - 3; // legacy eip 155
            if (!tx.type.isNull && tx.type.get != TransactionType.LEGACY)
            {
                lastIndex = serialized.length;
            }
            rawTx = rlpEncode(serialized[0 .. lastIndex] ~ [
                    v.convTo!bytes.cutBytes, signature.r.cutBytes,
                    signature.s.cutBytes
                    ]);
            if (!tx.type.isNull && tx.type.get != TransactionType.LEGACY)
            {
                rawTx = tx.type.get ~ rawTx;
            }
        }
        return rawTx;
    }
}
