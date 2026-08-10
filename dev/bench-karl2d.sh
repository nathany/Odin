#!/usr/bin/env bash
# Compile-time benchmark: karl2d snake example (Git Bash on Windows).
# Run it a few times; ignore the first run (cold file cache).
set -eu

KARL2D=$HOME/src/github.com/karl-zylinski/karl2d
FLAGS="-o:minimal -linker:radlink"
# FLAGS="-linker:radlink -debug"

odin build "$KARL2D/examples/snake" \
  $FLAGS -show-timings -out:snake.exe

# Lines/files/packages the compiler parsed (needs BOTH extra flags):
# odin build "$KARL2D/examples/snake" $FLAGS -show-more-timings -show-debug-messages \
#   -out:snake.exe 2>&1 | grep -E "^Total (Time|Lines|Files|Packages)"

# Parapoly instantiations + per-module instruction counts (undocumented flag):
# odin build "$KARL2D/examples/snake" $FLAGS -build-diagnostics -out:snake.exe
