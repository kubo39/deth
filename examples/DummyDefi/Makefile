SOURCE = $(wildcard contracts/*.sol)
SOLCFLAGS = --abi --bin --optimize --overwrite -o views/build --base-path=contracts --include-path=node_modules

build: $(SOURCE)
	solc $(SOLCFLAGS) $(SOURCE)

clean:
	rm -rf views/build/*
