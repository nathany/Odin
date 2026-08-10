#!/usr/bin/env bash
# Compile-time benchmark: cat & onion (Git Bash on Windows).
# Same flags as build_no_hot_reload.bat, minus -debug, plus timing flags.
# Run it a few times; ignore the first run (cold file cache).
set -eu

CAT=$HOME/src/github.com/karl-zylinski/cat_and_onion_source
FLAGS="-linker:radlink"
# FLAGS="-linker:radlink -debug"

odin build "$CAT/main_release" \
  -define:RAYLIB_SHARED=true -define:EmbedAssets=false -collection:cat="$CAT" \
  $FLAGS -show-timings -out:cat-game.exe

# Lines/files/packages the compiler parsed (needs BOTH extra flags):
# odin build "$CAT/main_release" \
#   -define:RAYLIB_SHARED=true -define:EmbedAssets=false -collection:cat="$CAT" \
#   $FLAGS -show-more-timings -show-debug-messages \
#   -out:cat-game.exe 2>&1 | grep -E "^Total (Time|Lines|Files|Packages)"

# Parapoly instantiations + per-module instruction counts (undocumented flag):
# odin build "$CAT/main_release" \
#   -define:RAYLIB_SHARED=true -define:EmbedAssets=false -collection:cat="$CAT" \
#   $FLAGS -build-diagnostics -out:cat-game.exe
