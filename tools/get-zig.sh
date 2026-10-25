#!/bin/bash
# Installs the Zig that Argus is pinned to (0.17.0, the release of 2026-10-01) into .toolchain/,
# verified against the SHA-256 published at https://ziglang.org/download/index.json, and points
# .toolchain/zig at it. The Makefile and the app both use .toolchain/zig before any zig on PATH.
#   tools/get-zig.sh            # or: make zig
# If minisign is installed, the download is also checked against Zig's signing key.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=0.17.0
ARCH="$(uname -m)"
case "$(uname -s)-$ARCH" in
    Darwin-arm64) NAME="zig-aarch64-macos-$VERSION"; SHA256=b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a ;;
    # Linux (a VM, CI): enough for `make harness` on .zig themes; the app itself needs a Mac.
    Linux-x86_64) NAME="zig-x86_64-linux-$VERSION"; SHA256=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026 ;;
    Linux-aarch64) NAME="zig-aarch64-linux-$VERSION"; SHA256=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8 ;;
    *) echo "Argus runs on Apple silicon (arm64); the theme harness also on Linux x86_64/aarch64. This is $(uname -s) $ARCH." >&2; exit 1 ;;
esac
sha256() { if command -v shasum >/dev/null; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }
URL="https://ziglang.org/download/$VERSION/$NAME.tar.xz"
MINISIGN_KEY=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U

if [ -x .toolchain/zig ] && [ "$(.toolchain/zig version 2>/dev/null)" = "$VERSION" ]; then
    echo "Zig $VERSION already installed: .toolchain/zig"
    exit 0
fi

mkdir -p .toolchain
tarball=".toolchain/$NAME.tar.xz"
if [ ! -f "$tarball" ] || ! echo "$SHA256  $tarball" | sha256 -c --status; then
    echo "Downloading $URL"
    curl -fL --retry 3 --progress-bar -o "$tarball.part" "$URL"
    mv "$tarball.part" "$tarball"
fi
echo "$SHA256  $tarball" | sha256 -c - || { echo "Checksum mismatch: removing $tarball" >&2; rm -f "$tarball"; exit 1; }

if command -v minisign >/dev/null; then
    curl -fsSL --retry 3 -o "$tarball.minisig" "$URL.minisig"
    minisign -Vm "$tarball" -x "$tarball.minisig" -P "$MINISIGN_KEY"
fi

rm -rf ".toolchain/$NAME"
tar -xJf "$tarball" -C .toolchain
ln -sfn "$NAME/zig" .toolchain/zig
rm -f "$tarball" "$tarball.minisig"
echo "Installed: .toolchain/zig -> $(.toolchain/zig version)"
