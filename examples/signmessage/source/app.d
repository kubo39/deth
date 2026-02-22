// EIP-191 message signing and verification example.
// https://eips.ethereum.org/EIPS/eip-191
//
// No network connection required - signing and verification are purely local.

import std.stdio;

import deth;

void main()
{
    // Anvil's first default account private key
    auto signer = new Signer(
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    );
    const signerAddress = signer.address;
    writeln("Signer:    ", signerAddress.convTo!string.ox);

    // Sign a message using EIP-191 (personal_sign format)
    auto message = "Hello, Ethereum!";
    auto sig = signer.signMessage(message);

    // Ethereum encodes the recovery ID as v = recid + 27
    ubyte v = cast(ubyte)(sig.recid + 27);
    writefln("Signature: r=%s s=%s v=%d",
        sig.r.convTo!string.ox, sig.s.convTo!string.ox, v);

    // Recover signer address from message + signature
    const recovered = recoverMessageSigner(message, sig);
    writeln("Recovered: ", recovered.convTo!string.ox);

    assert(recovered == signerAddress);
    writeln("Verification: OK");
}
