#!/bin/sh

set -ex
nohup anvil --balance 1000000 &
dub test
dub run deth:devtest
