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
[ "$ARCH" = "arm64" ] || { echo "Argus runs on Apple silicon (arm64) only; this Mac is $ARCH." >&2; exit 1; }
NAME="zig-aarch64-macos-$VERSION"
SHA256=b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a
URL="https://ziglang.org/download/$VERSION/$NAME.tar.xz"
MINISIGN_KEY=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U

if [ -x .toolchain/zig ] && [ "$(.toolchain/zig version 2>/dev/null)" = "$VERSION" ]; then
    echo "Zig $VERSION already installed: .toolchain/zig"
    exit 0
fi

mkdir -p .toolchain
tarball=".toolchain/$NAME.tar.xz"
if [ ! -f "$tarball" ] || ! echo "$SHA256  $tarball" | shasum -a 256 -c --status; then
    echo "Downloading $URL"
    curl -fL --retry 3 --progress-bar -o "$tarball.part" "$URL"
    mv "$tarball.part" "$tarball"
fi
echo "$SHA256  $tarball" | shasum -a 256 -c - || { echo "Checksum mismatch: removing $tarball" >&2; rm -f "$tarball"; exit 1; }

if command -v minisign >/dev/null; then
    curl -fsSL --retry 3 -o "$tarball.minisig" "$URL.minisig"
    minisign -Vm "$tarball" -x "$tarball.minisig" -P "$MINISIGN_KEY"
fi

rm -rf ".toolchain/$NAME"
tar -xJf "$tarball" -C .toolchain
ln -sfn "$NAME/zig" .toolchain/zig
rm -f "$tarball" "$tarball.minisig"
echo "Installed: .toolchain/zig -> $(.toolchain/zig version)"
