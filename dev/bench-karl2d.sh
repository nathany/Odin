#!/usr/bin/env bash
set -eu

KARL2D=$HOME/src/github.com/karl-zylinski/karl2d
FLAGS=""
# FLAGS="-debug"

odin build "$KARL2D/examples/snake" $FLAGS -show-timings -out:snake

# Lines/files/packages the compiler parsed (needs BOTH extra flags):
# odin build "$KARL2D/examples/snake" $FLAGS -show-more-timings -show-debug-messages \
#   -out:snake.exe 2>&1 | grep -E "^Total (Time|Lines|Files|Packages)"
