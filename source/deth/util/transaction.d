module deth.util.transaction;

import core.sync;
import std.array : replace;
import std.bigint : BigInt;
import std.conv : to;
import std.digest : toHexString;
import std.exception;
import std.format;
import std.json : JSONValue;
import std.sumtype;
import std.typecons : Nullable, nullable;

import deth.util.types;
import deth.rpcconnector : RPCConnector;

import rlp.encode : encode, encodeLength, lengthOfPayloadLength;
import rlp.header;
import secp256k1 : Signature;

// https://eips.ethereum.org/EIPS/eip-2718
///
enum TransactionType : ubyte
{
    LEGACY  = 0,
    EIP2930 = 1,
    EIP1559 = 2,
}

alias Transaction = SumType!(
    LegacyTransaction,
    EIP2930Transaction,
    EIP1559Transaction,
);

///
JSONValue toJSON(const Transaction tx) pure @safe
{
    return tx.match!(
        (const LegacyTransaction legacyTx) => legacyTx.toJSON,
        (const EIP2930Transaction eip2930Tx) => eip2930Tx.toJSON,
        (const EIP1559Transaction eip1559Tx) => eip1559Tx.toJSON,
    );
}

/// Get 'from' field from Transaction (SumType)
Nullable!Address getFrom(const Transaction tx) pure @safe nothrow
{
    return tx.match!(
        (const LegacyTransaction t) => t.from,
        (const EIP2930Transaction t) => t.from,
        (const EIP1559Transaction t) => t.from,
    );
}

/// Get 'to' field from Transaction (SumType)
Nullable!Address getTo(const Transaction tx) pure @safe nothrow
{
    return tx.match!(
        (const LegacyTransaction t) => t.to,
        (const EIP2930Transaction t) => t.to,
        (const EIP1559Transaction t) => t.to,
    );
}

/// Serialize Transaction to RLP for signing
bytes serializeToRLP(const Transaction tx) pure @safe
{
    return tx.match!(
        (const LegacyTransaction t) => t.serializeToRLP(),
        (const EIP2930Transaction t) => t.serializeToRLP(),
        (const EIP1559Transaction t) => t.serializeToRLP(),
    );
}

/// Serialize Transaction to signed RLP
bytes serializeToSignedRLP(const Transaction tx, Signature signature) pure @safe
{
    return tx.match!(
        (const LegacyTransaction t) => t.serializeToSignedRLP(signature),
        (const EIP2930Transaction t) => t.serializeToSignedRLP(signature),
        (const EIP1559Transaction t) => t.serializeToSignedRLP(signature),
    );
}

///
struct EIP2930Transaction
{
    ///
    Nullable!Address from;
    ///
    Nullable!ulong chainid;
    ///
    Nullable!ulong nonce;
    ///
    Nullable!BigInt gasPrice;
    ///
    Nullable!BigInt gas;
    ///
    Nullable!Address to;
    ///
    Nullable!BigInt value;
    ///
    Nullable!bytes data = [];
    ///
    Nullable!AccessList accessList;

    ///
    TransactionType type() pure const nothrow @safe
    {
        return TransactionType.EIP2930;
    }

    ///
    JSONValue toJSON() pure const @safe
    {
        string[string] result;
        static foreach (field; [
                "from", "to", "gasPrice", "gas", "value", "data",
            ])
        {
            mixin(q{if (!%s.isNull)
                result[`%s`] = %s.get.convTo!string.ox;}.format(field, field, field));
        }
        static foreach (field; [
                "chainid", "accessList",
            ])
        {
            mixin(q{if (!%s.isNull)
                result[`%s`] = %s.get.to!string;}.format(field, field, field));
        }
        if (!nonce.isNull)
            result["nonce"] = nonce.get.to!string(16).ox;
        return result.JSONValue;
    }

    ///
    bytes serializeToRLP() pure const @safe
    {
        bytes rlpTx = [type];
        const payloadLen =
            chainid.encodeLength() +
            nonce.encodeLength() +
            gasPrice.encodeLength() +
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            accessList.encodeLength();
        Header header = { isList: true, payloadLen: payloadLen };
        rlpTx.reserve(payloadLen + lengthOfPayloadLength(payloadLen));
        header.encodeHeader(rlpTx);
        chainid.encode(rlpTx);
        nonce.encode(rlpTx);
        gasPrice.encode(rlpTx);
        gas.encode(rlpTx);
        to.encode(rlpTx);
        value.encode(rlpTx);
        data.encode(rlpTx);
        accessList.encode(rlpTx);

        return rlpTx;
    }

    ///
    bytes serializeToSignedRLP(Signature signature) pure const @safe
    {
        bytes signedTx = [type];
        const payloadLen =
            chainid.encodeLength() +
            nonce.encodeLength() +
            gasPrice.encodeLength() +
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            accessList.encodeLength() +
            (cast(bool) signature.recid).encodeLength() +
            signature.r.encodeLength() +
            signature.s.encodeLength();
        Header signedTxHeader = { isList: true, payloadLen: payloadLen };
        signedTx.reserve(payloadLen + lengthOfPayloadLength(payloadLen));
        signedTxHeader.encodeHeader(signedTx);
        chainid.encode(signedTx);
        nonce.encode(signedTx);
        gasPrice.encode(signedTx);
        gas.encode(signedTx);
        to.encode(signedTx);
        value.encode(signedTx);
        data.encode(signedTx);
        accessList.encode(signedTx);
        (cast(bool) signature.recid).encode(signedTx);
        signature.r.encode(signedTx);
        signature.s.encode(signedTx);

        return signedTx;
    }
}

@("eip-2930 encoding test")
private unittest
{
    // the case is taken from https://github.com/ethers-io/ethers.js
    AccessListItem[] accessList = [
        AccessListItem(
            "0x8a632c23bf807681570c3fb6632ce99fd98bdb23".convTo!Address,
            [
                "0x1c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25c".BigInt,
                "0x2b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919".BigInt,
                "0xc266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5".BigInt,
                "0xf49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824e".BigInt
            ]
        ),
        AccessListItem(
            "0x2d78b31ba09e8a2888d655e3d000fe95c63789c4".convTo!Address,
            [
                "0x1c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25c".BigInt,
                "0x2b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919".BigInt,
                "0xc266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5".BigInt,
                "0xf49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824e".BigInt
            ]
        ),
        AccessListItem(
            "0x3199b3433ee7f3edcae901cbce64c4e81125f7da".convTo!Address,
            [
                "0x1c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25c".BigInt,
                "0x2b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919".BigInt,
                "0xc266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5".BigInt,
                "0xf49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824e".BigInt
            ]
        ),
        AccessListItem(
            "0xb8d669949683a728f76919fe2cc9896216e00a81".convTo!Address,
            [
                "0x1c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25c".BigInt,
                "0x2b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919".BigInt,
                "0xc266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5".BigInt,
                "0xf49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824e".BigInt
            ]
        )
    ];
    EIP2930Transaction tx = {
        chainid: 0xef36a8,
        nonce: 577,
        gas: "0xbe431918".BigInt,
        gasPrice: "0xb3b1aaeb58".BigInt,
        to: "0x4d1060d970674619005137921969b4bfe3eea6b8".convTo!Address,
        value: "0xc72c".BigInt,
        data: (
            "0xe07f2239c398167e747939f64b2ed9458db8aa10eb367bfab1976a0bc6693cf152dd8d13aa16e4d655a38d6ac64eae0932e1" ~
        "3d649f9516fca834cd5a49c7b6e5ba1286a30eea1ac2e89c78441c5418250f8e30").convTo!bytes,
        accessList: accessList.nullable,
    };
    const rlpTx = tx.serializeToRLP();
    const expected =
                   ("0x01f902f683ef36a882024185b3b1aaeb5884be431918944d1060d970674619005137921969b4bfe3eea6b882c72cb8" ~
    "53e07f2239c398167e747939f64b2ed9458db8aa10eb367bfab1976a0bc6693cf152dd8d13aa16e4d655a38d6ac64eae0932e13d649f9516" ~
    "fca834cd5a49c7b6e5ba1286a30eea1ac2e89c78441c5418250f8e30f90274f89b948a632c23bf807681570c3fb6632ce99fd98bdb23f884" ~
    "a01c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25ca02b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c" ~
    "5a2b317c740630901919a0c266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5a0f49934500a155bedea4f0bf2" ~
    "5bfc62161fcb74fbf17ca480333f4747d5ad824ef89b942d78b31ba09e8a2888d655e3d000fe95c63789c4f884a01c3124f271ea52d9e881" ~
    "bdd52c63020fb7c08a1b96263030415e4bc8146db25ca02b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919a0" ~
    "c266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5a0f49934500a155bedea4f0bf25bfc62161fcb74fbf17ca4" ~
    "80333f4747d5ad824ef89b943199b3433ee7f3edcae901cbce64c4e81125f7daf884a01c3124f271ea52d9e881bdd52c63020fb7c08a1b96" ~
    "263030415e4bc8146db25ca02b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919a0c266c51508b93a8f933e2e" ~
    "64505e458ac26cdb93e8e0bc7bd1609552b6210aa5a0f49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824ef89b" ~
    "94b8d669949683a728f76919fe2cc9896216e00a81f884a01c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25c" ~
    "a02b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919a0c266c51508b93a8f933e2e64505e458ac26cdb93e8e0" ~
    "bc7bd1609552b6210aa5a0f49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824e").convTo!bytes;
    assert(rlpTx == expected);

    import secp256k1 : secp256k1;
    auto privateKey = "0x77065b8ddb2f89d3d2d83f46d0147efc081e3a3f1012406c698a9ce364b324e9".convTo!Hash;
    auto c = new secp256k1(privateKey);
    const signedRlpTx = tx.serializeToSignedRLP(c.sign(rlpTx));
    const expectedSigned =
                         ("0x01f9033983ef36a882024185b3b1aaeb5884be431918944d1060d970674619005137921969b4bfe3eea6b882" ~
    "c72cb853e07f2239c398167e747939f64b2ed9458db8aa10eb367bfab1976a0bc6693cf152dd8d13aa16e4d655a38d6ac64eae0932e13d64" ~
    "9f9516fca834cd5a49c7b6e5ba1286a30eea1ac2e89c78441c5418250f8e30f90274f89b948a632c23bf807681570c3fb6632ce99fd98bdb" ~
    "23f884a01c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25ca02b6d4aa754fa44f0e86e6fa0a936048674ffc4" ~
    "fef24c5a2b317c740630901919a0c266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5a0f49934500a155bedea" ~
    "4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824ef89b942d78b31ba09e8a2888d655e3d000fe95c63789c4f884a01c3124f271ea52" ~
    "d9e881bdd52c63020fb7c08a1b96263030415e4bc8146db25ca02b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c74063090" ~
    "1919a0c266c51508b93a8f933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5a0f49934500a155bedea4f0bf25bfc62161fcb74fb" ~
    "f17ca480333f4747d5ad824ef89b943199b3433ee7f3edcae901cbce64c4e81125f7daf884a01c3124f271ea52d9e881bdd52c63020fb7c0" ~
    "8a1b96263030415e4bc8146db25ca02b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919a0c266c51508b93a8f" ~
    "933e2e64505e458ac26cdb93e8e0bc7bd1609552b6210aa5a0f49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad82" ~
    "4ef89b94b8d669949683a728f76919fe2cc9896216e00a81f884a01c3124f271ea52d9e881bdd52c63020fb7c08a1b96263030415e4bc814" ~
    "6db25ca02b6d4aa754fa44f0e86e6fa0a936048674ffc4fef24c5a2b317c740630901919a0c266c51508b93a8f933e2e64505e458ac26cdb" ~
    "93e8e0bc7bd1609552b6210aa5a0f49934500a155bedea4f0bf25bfc62161fcb74fbf17ca480333f4747d5ad824e80a0512308d1c72f697a" ~
    "25785a9c2ce00a55ba530c49a024f46f0cc26dd0e8358576a0574f05518fc3f6ba63cfb917242f2220fb470c8166135079c7bb7fc36054d5d7"
                   ).convTo!bytes;
    assert(signedRlpTx == expectedSigned);
}

///
struct EIP1559Transaction
{
    ///
    Nullable!Address from;
    ///
    Nullable!ulong chainid;
    ///
    Nullable!ulong nonce;
    ///
    Nullable!BigInt maxPriorityFeePerGas;
    ///
    Nullable!BigInt maxFeePerGas;
    ///
    Nullable!BigInt gas;
    ///
    Nullable!Address to;
    ///
    Nullable!BigInt value;
    ///
    Nullable!bytes data = [];
    ///
    Nullable!AccessList accessList;

    ///
    TransactionType type() pure const nothrow @safe
    {
        return TransactionType.EIP1559;
    }

    ///
    JSONValue toJSON() pure const @safe
    {
        string[string] result;
        static foreach (field; [
                "from", "to", "gas", "value", "data",
            ])
        {
            mixin(q{if (!%s.isNull)
                result[`%s`] = %s.get.convTo!string.ox;}.format(field, field, field));
        }
        static foreach (field; [
                "chainid", "maxFeePerGas", "maxPriorityFeePerGas", "accessList",
            ])
        {
            mixin(q{if (!%s.isNull)
                result[`%s`] = %s.get.to!string;}.format(field, field, field));
        }
        if (!nonce.isNull)
            result["nonce"] = nonce.get.to!string(16).ox;
        return result.JSONValue;
    }

    ///
    bytes serializeToRLP() pure const @safe
    {
        bytes rlpTx = [type];
        const payloadLen =
            chainid.encodeLength() +
            nonce.encodeLength() +
            maxPriorityFeePerGas.encodeLength() +
            maxFeePerGas.encodeLength() +
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            accessList.encodeLength();
        Header header = { isList: true, payloadLen: payloadLen };
        rlpTx.reserve(payloadLen + lengthOfPayloadLength(payloadLen));
        header.encodeHeader(rlpTx);
        chainid.encode(rlpTx);
        nonce.encode(rlpTx);
        maxPriorityFeePerGas.encode(rlpTx);
        maxFeePerGas.encode(rlpTx);
        gas.encode(rlpTx);
        to.encode(rlpTx);
        value.encode(rlpTx);
        data.encode(rlpTx);
        accessList.encode(rlpTx);

        return rlpTx;
    }

    ///
    bytes serializeToSignedRLP(Signature signature) pure const @safe
    {
        bytes signedTx = [type];
        const payloadLen =
            chainid.encodeLength() +
            nonce.encodeLength() +
            maxPriorityFeePerGas.encodeLength() +
            maxFeePerGas.encodeLength() +
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            accessList.encodeLength() +
            (cast(bool) signature.recid).encodeLength() +
            signature.r.encodeLength() +
            signature.s.encodeLength();
        Header signedTxHeader = { isList: true, payloadLen: payloadLen };
        signedTx.reserve(payloadLen + lengthOfPayloadLength(payloadLen));
        signedTxHeader.encodeHeader(signedTx);
        chainid.encode(signedTx);
        nonce.encode(signedTx);
        maxPriorityFeePerGas.encode(signedTx);
        maxFeePerGas.encode(signedTx);
        gas.encode(signedTx);
        to.encode(signedTx);
        value.encode(signedTx);
        data.encode(signedTx);
        accessList.encode(signedTx);
        (cast(bool) signature.recid).encode(signedTx);
        signature.r.encode(signedTx);
        signature.s.encode(signedTx);

        return signedTx;
    }
}

@("eip-1559 encoding test")
unittest
{
    EIP1559Transaction tx = {
        chainid: 1,
        nonce: 0,
        maxPriorityFeePerGas: "2000000000".BigInt,
        maxFeePerGas: "3000000000".BigInt,
        gas: "78009".BigInt,
        to: "0x6b175474e89094c44da98b954eedeac495271d0f".convTo!Address,
        value: "0".BigInt,
        data:
        ("0xa9059cbb0000000000000000000000005322b34c88ed0691971bf52a7047448f0f4efc8400000000000000000000000000000" ~
         "00000000000000000001bc16d674ec80000").convTo!bytes,
    };
    const rlpTx = tx.serializeToRLP();
    const expected =
        ("0x02f86D0180847735940084b2d05e00830130b9946b175474e89094c44da98b954eedeac495271d0f80b844a9059cbb0" ~
   "000000000000000000000005322b34c88ed0691971bf52a7047448f0f4efc840000000000000000000000000000000000000000000000001b" ~
   "c16d674ec80000c0").convTo!bytes;
   assert(rlpTx == expected);
}

///
struct LegacyTransaction
{
    ///
    Nullable!Address from;
    ///
    Nullable!Address to;
    ///
    Nullable!BigInt gas;
    ///
    Nullable!BigInt gasPrice;
    ///
    Nullable!BigInt value;
    ///
    Nullable!bytes data = [];
    ///
    Nullable!ulong nonce;
    ///
    Nullable!ulong chainid;

    invariant
    {
        assert(gas.isNull || gas.get >= 0);
        assert(gasPrice.isNull || gasPrice.get >= 0);
        assert(value.isNull || value.get >= 0);
    }

    ///
    JSONValue toJSON() pure const @safe
    {
        string[string] result;
        static foreach (field; [
                "from", "to", "gas", "gasPrice", "value", "data",
            ])
        {
            mixin(q{if (!%s.isNull)
                    result["%s"] = %s.get.convTo!string.ox;}.format(field, field, field));
        }
        if (!nonce.isNull)
            result["nonce"] = nonce.get.to!string(16).ox;
        return result.JSONValue;
    }

    ///
    bytes serializeToRLP() pure const @safe
    {
        bytes rlpTx;
        auto payloadLen =
            nonce.encodeLength() +
            gasPrice.encodeLength()+
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength();
        if (!chainid.isNull)
        {
            payloadLen += chainid.encodeLength();
            payloadLen += 2;
        }
        Header header = { isList: true, payloadLen: payloadLen };
        rlpTx.reserve(payloadLen + lengthOfPayloadLength(payloadLen));
        header.encodeHeader(rlpTx);
        nonce.encode(rlpTx);
        gasPrice.encode(rlpTx);
        gas.encode(rlpTx);
        to.encode(rlpTx);
        value.encode(rlpTx);
        data.encode(rlpTx);
        if (!chainid.isNull)
        {
            chainid.encode(rlpTx);
            rlpTx ~= [0x80, 0x80];
        }

        return rlpTx;
    }

    ///
    bytes serializeToSignedRLP(Signature signature) pure const @safe
    {
        bytes signedTx;
        const ulong v = chainid.isNull
            ? 27 + signature.recid
            : signature.recid + chainid.get * 2 + 35 /* eip 155 signing */ ;
        const payloadLen =
            nonce.encodeLength() +
            gasPrice.encodeLength()+
            gas.encodeLength() +
            to.encodeLength() +
            value.encodeLength() +
            data.encodeLength() +
            v.encodeLength() +
            signature.r.encodeLength() +
            signature.s.encodeLength();
        Header signedTxHeader = { isList: true, payloadLen: payloadLen };
        signedTx.reserve(payloadLen + lengthOfPayloadLength(payloadLen));
        signedTxHeader.encodeHeader(signedTx);
        nonce.encode(signedTx);
        gasPrice.encode(signedTx);
        gas.encode(signedTx);
        to.encode(signedTx);
        value.encode(signedTx);
        data.encode(signedTx);
        v.encode(signedTx);
        signature.r.encode(signedTx);
        signature.s.encode(signedTx);

        return signedTx;
    }
}

static foreach (f, t; [
        "From": "Address",
        "To": "Address",
        "Gas": "BigInt",
        "GasPrice": "BigInt",
        "Value": "BigInt",
        "Data": "bytes",
        "Nonce": "ulong",
        "ChainId": "ulong",
        "MaxPriorityFeePerGas": "BigInt",
        "MaxFeePerGas": "BigInt",
        "AccessList": "bytes",
    ])
{
    mixin NamedParameter!(f, t);
}

alias SendableTransaction = SumType!(
    SendableLegacyTransaction,
    SendableEIP2930Transaction,
    SendableEIP1559Transaction,
);

///
Hash send(ARGS...)(SendableTransaction tx, ARGS params) @safe
{
    return tx.match!(
        (SendableLegacyTransaction legacyTx) => legacyTx.send(params),
        (SendableEIP2930Transaction eip2930Tx) => eip2930Tx.send(params),
        (SendableEIP1559Transaction eip1559Tx) => eip1559Tx.send(params),
    );
}

///
struct SendableEIP1559Transaction
{
    ///
    EIP1559Transaction tx;
    private RPCConnector conn;

    ///
    Hash send(ARGS...)(ARGS params) @safe
    {
        static foreach (i; 0 .. ARGS.length)
        {
            static if (is(ARGS[i] == From))
                tx.from = params[i].value;
            else static if (is(ARGS[i] == To))
                tx.to = params[i].value;
            else static if (is(ARGS[i] == Value))
                tx.value = params[i].value;
            else static if (is(ARGS[i] == Gas))
                tx.gas = params[i].value;
            else static if (is(ARGS[i] == Nonce))
                tx.nonce = params[i].value;
            else static if (is(ARGS[i] == Data))
                tx.data = params[i].value;
            else static if (is(ARGS[i] == ChainId))
                tx.chainid = params[i].value;
            else static if (is(ARGS[i] == MaxPriorityFeePerGas))
                tx.maxPriorityFeePerGas = params[i].value;
            else static if (is(ARGS[i] == MaxFeePerGas))
                tx.maxFeePerGas = params[i].value;
            else static if (is(ARGS[i] == AccessList))
                tx.accessList = params[i].value;
            else
                static assert(0, "Not supported param " ~ ARGS[i].stringof);
        }

        if (tx.from.isNull)
        {
            auto accList = conn.accounts ~ conn.remoteAccounts;
            enforce(accList.length > 0, " No accounts are unlocked");
            tx.from = accList[0];
        }
        if (tx.gas.isNull)
        {
            tx.gas = conn.estimateGas(Transaction(tx)) * conn.gasEstimatePercentage / 100;
        }
        synchronized
        {
            if (tx.nonce.isNull)
            {
                tx.nonce = conn.getTransactionCount(tx.from.get);
            }
            if (conn.isUnlocked(tx.from.get))
            {
                return conn.sendRawTransaction(Transaction(tx));
            }
            else if (conn.isUnlockedRemote(tx.from.get))
            {
                return conn.sendTransaction(Transaction(tx));
            }
        }
        assert(0);
    }
}

///
struct SendableEIP2930Transaction
{
    ///
    EIP2930Transaction tx;
    private RPCConnector conn;

    ///
    Hash send(ARGS...)(ARGS params) @safe
    {
        static foreach (i; 0 .. ARGS.length)
        {
            static if (is(ARGS[i] == From))
                tx.from = params[i].value;
            else static if (is(ARGS[i] == To))
                tx.to = params[i].value;
            else static if (is(ARGS[i] == Value))
                tx.value = params[i].value;
            else static if (is(ARGS[i] == Gas))
                tx.gas = params[i].value;
            else static if (is(ARGS[i] == Nonce))
                tx.nonce = params[i].value;
            else static if (is(ARGS[i] == Data))
                tx.data = params[i].value;
            else static if (is(ARGS[i] == ChainId))
                tx.chainid = params[i].value;
            else static if (is(ARGS[i] == GasPrice))
                tx.gasPrice = params[i].value;
            else static if (is(ARGS[i] == AccessList))
                tx.accessList = params[i].value;
            else
                static assert(0, "Not supported param " ~ ARGS[i].stringof);
        }

        if (tx.from.isNull)
        {
            auto accList = conn.accounts ~ conn.remoteAccounts;
            enforce(accList.length > 0, " No accounts are unlocked");
            tx.from = accList[0];
        }
        if (tx.gas.isNull)
        {
            tx.gas = conn.estimateGas(Transaction(tx)) * conn.gasEstimatePercentage / 100;
        }
        synchronized
        {
            if (tx.nonce.isNull)
            {
                tx.nonce = conn.getTransactionCount(tx.from.get);
            }
            if (conn.isUnlocked(tx.from.get))
            {
                return conn.sendRawTransaction(Transaction(tx));
            }
            else if (conn.isUnlockedRemote(tx.from.get))
            {
                return conn.sendTransaction(Transaction(tx));
            }
        }
        assert(0);
    }
}

///
struct SendableLegacyTransaction
{
    ///
    LegacyTransaction tx;
    private RPCConnector conn;

    ///
    Hash send(ARGS...)(ARGS params) @safe
    {
        static foreach (i; 0 .. ARGS.length)
        {
            static if (is(ARGS[i] == From))
                tx.from = params[i].value;
            else static if (is(ARGS[i] == To))
                tx.to = params[i].value;
            else static if (is(ARGS[i] == Value))
                tx.value = params[i].value;
            else static if (is(ARGS[i] == Gas))
                tx.gas = params[i].value;
            else static if (is(ARGS[i] == GasPrice))
                tx.gasPrice = params[i].value;
            else static if (is(ARGS[i] == Nonce))
                tx.nonce = params[i].value;
            else static if (is(ARGS[i] == Data))
                tx.data = params[i].value;
            else
                static assert(0, "Not supported param " ~ ARGS[i].stringof);
        }

        if (tx.from.isNull)
        {
            auto accList = conn.accounts ~ conn.remoteAccounts;
            enforce(accList.length > 0, " No accounts are unlocked");
            tx.from = accList[0];
        }
        if (tx.gas.isNull)
        {
            tx.gas = conn.estimateGas(Transaction(tx)) * conn.gasEstimatePercentage / 100;
        }
        if (tx.gasPrice.isNull)
        {
            tx.gasPrice = conn.gasPrice;
        }
        synchronized
        {
            if (tx.nonce.isNull)
            {
                tx.nonce = conn.getTransactionCount(tx.from.get);
            }
            if (conn.isUnlocked(tx.from.get))
            {
                return conn.sendRawTransaction(Transaction(tx));
            }
            else if (conn.isUnlockedRemote(tx.from.get))
            {
                return conn.sendTransaction(Transaction(tx));
            }
        }
        assert(0);
    }
}

///
mixin template NamedParameter(string fieldName, string type)
{
    mixin(q{
            struct %s
            {
            %s value;
            }
            }.format(fieldName, type));
}
