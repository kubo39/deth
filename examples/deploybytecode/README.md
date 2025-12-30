# Example: deploy bytecode

- Build the Counter contract.

```console
make build-sol
# or directly `solc --via-ir --abi --optimize --overwrite --bin -o views/artifacts/ contracts/Counter.sol`
```

- Run anvil in another terminal.

```console
anvil --balance 1000000
```

- Run the app.


```console
dub run
```
