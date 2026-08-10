#!/usr/bin/env bash
# Compile-time benchmark for the Odin core library (Git Bash on Windows).
# Run it a few times; ignore the first run (cold file cache).
#
# Odin has no `odin build ./...`, so we build the core unit-test executable
# WITHOUT running it (-build-mode:test). The tests_core package contains both
# test drivers (normal.odin and speed.odin), so this parses and typechecks
# ~282K lines and does LLVM codegen for everything the tests reach.
set -eu

ODIN_REPO=$HOME/src/github.com/odin-lang/Odin
FLAGS="-o:minimal -linker:radlink"
# FLAGS="-debug -linker:radlink"

odin build "$ODIN_REPO/tests/core" -all-packages -build-mode:test \
  $FLAGS -show-timings -out:core-tests.exe
