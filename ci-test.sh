#!/bin/sh

set -ex

# Start anvil in background and save PID
nohup anvil --balance 1000000 > /dev/null 2>&1 &
ANVIL_PID=$!

# Cleanup function to kill anvil
cleanup() {
    echo "Cleaning up anvil process..."
    kill $ANVIL_PID 2>/dev/null || true
    wait $ANVIL_PID 2>/dev/null || true
}

# Set trap to cleanup on exit (both success and failure)
trap cleanup EXIT INT TERM

# Wait for anvil to be ready
sleep 2

# Run tests
dub test -q -- --threads=1
dub run deth:devtest -q
dub run deth:transfer -q
dub run deth:deploybytecode -q
