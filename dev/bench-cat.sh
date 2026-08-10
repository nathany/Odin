#!/usr/bin/env bash
set -eu

CAT=$HOME/Development/odin/cat_and_onion_source_2024-12-20
FLAGS=""
# FLAGS="-debug"

odin build "$CAT/main_release" \
  -define:RAYLIB_SHARED=true -define:EmbedAssets=false -collection:cat="$CAT" \
  $FLAGS -show-timings -out:cat-game

# Lines/files/packages the compiler parsed (needs BOTH extra flags):
# odin build "$CAT/main_release" \
#   -define:RAYLIB_SHARED=true -define:EmbedAssets=false -collection:cat="$CAT" \
#   $FLAGS -show-more-timings -show-debug-messages \
#   -out:cat-game 2>&1 | grep -E "^Total (Time|Lines|Files|Packages)"
