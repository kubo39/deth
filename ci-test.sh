#!/bin/sh

set -ex
nohup anvil --base-fee=0 --balance=1000000 &
dub test
dub run deth:devtest
