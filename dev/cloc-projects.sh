#!/usr/bin/env bash
# Line counts for the benchmarked projects, for comparison with the
# compiler's 'Total Lines' (bench-core-details.sh). cloc counts code lines
# only (no comments/blanks) across ALL platforms' files, so it won't match
# the compiler's number exactly.
set -eu

ODIN_REPO=$HOME/src/github.com/odin-lang/Odin
KARL2D=$HOME/src/github.com/karl-zylinski/karl2d
CAT=$HOME/src/github.com/karl-zylinski/cat_and_onion_source

echo "== karl2d library (excluding examples) =="
cloc --include-lang=Odin --quiet --exclude-dir=examples "$KARL2D"

echo "== karl2d snake example =="
cloc --include-lang=Odin --quiet "$KARL2D/examples/snake"

echo "== cat & onion =="
cloc --include-lang=Odin --quiet "$CAT"

echo "== Odin core library =="
cloc --include-lang=Odin --quiet "$ODIN_REPO/core"

echo "== Odin core tests =="
cloc --include-lang=Odin --quiet "$ODIN_REPO/tests/core"

echo "== Odin core library + tests =="
cloc --include-lang=Odin --quiet "$ODIN_REPO/tests/core" "$ODIN_REPO/core"
