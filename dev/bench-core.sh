#!/usr/bin/env bash
set -eu

ODIN_REPO=$HOME/src/github.com/odin-lang/Odin
FLAGS=""
# FLAGS="-debug"

odin build "$ODIN_REPO/tests/core" -all-packages -build-mode:test \
  $FLAGS -show-timings -out:core-tests

# odin build "$ODIN_REPO/tests/core" -all-packages -build-mode:test \
#   $FLAGS -show-more-timings -show-debug-messages \
#   -out:core-tests 2>&1 | grep -E "^Total (Time|Lines|Files|Packages)|LLVM Object Generation"
