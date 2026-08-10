#!/usr/bin/env bash
# Supporting evidence for bench-core.sh: how many lines the compiler actually
# processed, and how much code survived into LLVM codegen.
set -eu

ODIN_REPO=$HOME/src/github.com/odin-lang/Odin
FLAGS="-o:minimal -linker:radlink"
BUILD=(odin build "$ODIN_REPO/tests/core" -all-packages
       -build-mode:test $FLAGS -out:core-tests.exe)

# echo "== parapoly + per-module diagnostics (full tables: core-diagnostics.txt) =="
# # -build-diagnostics is undocumented (not in -help): prints the top 100
# # polymorphic procedures with instantiation counts, then a per-module table
# # of instructions/procedures/globals. Output format may change between
# # releases.
# "${BUILD[@]}" -build-diagnostics 2>&1 > core-diagnostics.txt
# sed -n '1,10p' core-diagnostics.txt

echo
echo "== lines/files/packages parsed, and how many modules were emitted =="
# NOTE: the 'Total Lines' block prints only when -show-more-timings AND
# -show-debug-messages are both set. Lines are physical lines (including
# comments and blanks) of just the files matching the target platform.
"${BUILD[@]}" -show-more-timings -show-debug-messages 2>&1 |
  grep -E "^Total (Time|Lines|Files|Packages)|LLVM Object Generation"

echo
echo "== IR emitted per package (one .ll file per reached package) =="
# File size roughly reflects compile time. Packages with no .ll file were
# parsed and typechecked but contributed no machine code.
rm -rf core-ll && mkdir core-ll && cd core-ll
"${BUILD[@]}" -keep-temp-files > /dev/null 2>&1
echo "modules emitted: $(ls *.ll | wc -l)"
echo "total IR size:   $(du -ch *.ll | tail -1 | cut -f1)"
cd ..
