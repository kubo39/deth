/// PrivateKeys manipulator
module deth.wallet;

import std.bigint;
import std.experimental.logger;
import std.exception : enforce;
import secp256k1 : secp256k1;
import deth.util : Address, Hash, bytes, convTo, Transaction, ox;

import rlp.encode : encode, encodeLength;
import rlp.header;

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

        bytes rlpTx;
        Header header = { isList: true, payloadLen: 0 };
        header.payloadLen =
            tx.nonce.encodeLength() +
            tx.gasPrice.encodeLength()+
            tx.gas.encodeLength() +
            tx.to.encodeLength() +
            tx.value.encodeLength() +
            tx.data.encodeLength();
        if (!tx.chainid.isNull)
        {
            header.payloadLen += tx.chainid.encodeLength();
            header.payloadLen += 2;
        }
        header.encodeHeader(rlpTx);
        tx.nonce.encode(rlpTx);
        tx.gasPrice.encode(rlpTx);
        tx.gas.encode(rlpTx);
        tx.to.encode(rlpTx);
        tx.value.encode(rlpTx);
        tx.data.encode(rlpTx);
        if (!tx.chainid.isNull)
        {
            tx.chainid.encode(rlpTx);
            rlpTx ~= [0x80, 0x80];
        }

        debug logf("Rlp encoded tx %s", rlpTx.toHexString.ox);

        // the secp256k1 sign function calls keccak256() internally.
        auto signature = c.sign(rlpTx);
        bytes rawTx;
        Header rawTxHeader = { isList: true, payloadLen: 0 };
        ulong v = tx.chainid.isNull
            ? 27 + signature.recid
            : signature.recid + tx.chainid.get * 2 + 35 /* eip 155 signing */ ;
        rawTxHeader.payloadLen =
            tx.nonce.encodeLength() +
            tx.gasPrice.encodeLength()+
            tx.gas.encodeLength() +
            tx.to.encodeLength() +
            tx.value.encodeLength() +
            tx.data.encodeLength() +
            v.encodeLength() +
            signature.r.encodeLength() +
            signature.s.encodeLength();
        rawTxHeader.encodeHeader(rawTx);
        tx.nonce.encode(rawTx);
        tx.gasPrice.encode(rawTx);
        tx.gas.encode(rawTx);
        tx.to.encode(rawTx);
        tx.value.encode(rawTx);
        tx.data.encode(rawTx);
        v.encode(rawTx);
        signature.r.encode(rawTx);
        signature.s.encode(rawTx);
        return rawTx;
    }
}
