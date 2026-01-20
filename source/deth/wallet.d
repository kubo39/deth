/// PrivateKeys manipulator
module deth.wallet;

import deth.signer;
import deth.util.types : Address;

/// struct to store several private keys in a single wallet
struct Wallet
{
    this(ARGS...)(ARGS signers) @safe
    {
        foreach (signer; signers)
            addSigner(signer);
    }

    // add a signer.
    void addSigner(Signer signer) @safe
    {
        _signers[signer.address] = signer;
    }

    // returns a signer from an address.
    Signer getSigner(Address address) @safe
    {
        return _signers.get(address, null);
    }

    /// removes signer addresses from wallet
    /// Params:
    ///   signers = signer to remove
    void remove(Signer[] signers...) @safe
    {
        foreach (signer; signers)
            _signers.remove(signer.address);
    }

    /// Ditto, but for address.
    /// Params:
    ///   signers = signer to remove
    void remove(Address[] addresses...) @safe
    {
        foreach (address; addresses)
            _signers.remove(address);
    }

    /// Returns: list address stored in wallet;
    @property Address[] addresses() const pure @safe nothrow
    {
        return _signers.keys;
    }

private:
    Signer[Address] _signers;
}
