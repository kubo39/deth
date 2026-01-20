import std.conv : to;
import std.stdio;

import deth;

void main()
{
    auto conn = new RPCConnector("http://127.0.0.1:8545");

    const accounts = conn.remoteAccounts();
    const alice = accounts[0];
    const bob = accounts[1];

    // anvil's first default private key. (for alice)
    auto signer = new Signer(
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    );
    conn.wallet.addSigner(signer);

    const chainid = conn.net_version.to!ulong;
    LegacyTransaction tx = {
        to: bob,
        value: 100.wei,
        chainid: chainid
    };
    const txHash = SendableLegacyTransaction(tx, conn).send();
    const _receipt = conn.waitForTransactionReceipt(txHash);
    writeln("Sent transaction: ", txHash.convTo!string.ox);
}
