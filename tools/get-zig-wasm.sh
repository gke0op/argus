#!/bin/bash
# Builds zig.wasm, the Zig 0.17.0 compiler for wasm32-wasi that the bench page runs (web/zigc),
# from the official source tarball. The tarball is checked against the SHA-256 that
# https://ziglang.org/download/index.json lists for it, and that value against the one pinned
# here, so a changed index or tarball fails the build. Needs .toolchain/zig (tools/get-zig.sh)
# and jq. Writes .zig-wasm/zig.wasm (gitignored; CI caches it).
#
#   tools/get-zig-wasm.sh
#
# The build: no LLVM (so no LLVM-made code, only Zig's self-hosted wasm backend), -Ddev=wasm (the
# feature set that keeps Sema, so `build-* -fno-emit-bin` type-checks for any target, and the wasm
# backend and linker), no lib/ installed (the page ships the part a compile reads, web/zigc/bundle.zig).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=0.17.0
SHA256=b6c7f1728f043700d6529bac980800792f824256a9d2f1839b3d62beed0b8abd
URL="https://ziglang.org/download/$VERSION/zig-$VERSION.tar.xz"
MINISIGN_KEY=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
OUT=.zig-wasm
ZIG="$PWD/.toolchain/zig"

sha256() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }

if [ -f "$OUT/zig.wasm" ] && [ "$(cat "$OUT/source.sha256" 2>/dev/null)" = "$SHA256" ]; then
    echo "zig.wasm already built from $URL: $OUT/zig.wasm"
    exit 0
fi
[ -x "$ZIG" ] && [ "$("$ZIG" version)" = "$VERSION" ] || { echo "needs Zig $VERSION at .toolchain/zig: run tools/get-zig.sh" >&2; exit 1; }

listed=$(curl -fsSL --retry 3 https://ziglang.org/download/index.json | jq -r --arg v "$VERSION" '.[$v].src.shasum')
if [ "$listed" != "$SHA256" ]; then
    echo "ziglang.org/download/index.json lists $listed for the $VERSION source, not the pinned $SHA256" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "Downloading $URL"
curl -fL --retry 3 --progress-bar -o "$work/src.tar.xz" "$URL"
echo "$SHA256  $work/src.tar.xz" | sha256 -c - || { echo "Checksum mismatch for $URL" >&2; exit 1; }
if command -v minisign >/dev/null; then
    curl -fsSL --retry 3 -o "$work/src.tar.xz.minisig" "$URL.minisig"
    minisign -Vm "$work/src.tar.xz" -x "$work/src.tar.xz.minisig" -P "$MINISIGN_KEY"
fi
tar -xJf "$work/src.tar.xz" -C "$work"

(cd "$work/zig-$VERSION" && "$ZIG" build -Dtarget=wasm32-wasi -Doptimize=ReleaseSmall -Denable-llvm=false \
    -Ddev=wasm -Dversion-string="$VERSION" -Dno-lib --prefix "$work/out")
mkdir -p "$OUT"
cp "$work/out/bin/zig.wasm" "$OUT/zig.wasm"
echo "$SHA256" > "$OUT/source.sha256"
echo "Built $OUT/zig.wasm ($(wc -c < "$OUT/zig.wasm" | tr -d ' ') bytes) from $URL"
