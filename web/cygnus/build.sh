#!/bin/sh
# Builds web/cygnus/cygnus.wasm: the real Cygnus A theme (themes/Cygnus_A.zig) and the app's
# table layouts (src/gpu/bh_tables.zig), compiled to wasm32-freestanding. Run from the repo root.
set -eu
ZIG=${ZIG:-./.toolchain/zig}
"$ZIG" build-exe -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseFast -fstrip \
  --dep theme --dep bh_tables -Mroot=web/cygnus/cygnus_wasm.zig \
  -Mtheme=themes/Cygnus_A.zig -Mbh_tables=src/gpu/bh_tables.zig \
  -femit-bin=web/cygnus/cygnus.wasm
rm -f web/cygnus/cygnus.wasm.o
ls -l web/cygnus/cygnus.wasm
