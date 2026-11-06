#!/bin/sh
# web/zigc/build.sh: the bench page's in-browser compiler, into web/zigc/build/ (gitignored).
#
#   ZIG_WASM=path/to/zig.wasm web/zigc/build.sh      # or: make web-zigc ZIG_WASM=...
#
# ZIG_WASM is Zig 0.17.0 built for wasm32-wasi from the official source tarball (see
# .github/workflows/pages.yml, which builds it in CI, for the exact command). Writes:
#   zig.wasm.gz      the compiler (gzip -9n)
#   zig-lib.bin.gz   the std/compiler_rt import closure of the release's lib/ (web/zigc/bundle.zig)
#   support/...      runtime.zig, harness_gates.zig, the SDK and the kernel, at the paths the
#                    compile sees (web/zigc/zigc.js SUPPORT)
#   manifest.json    sizes and SHA-256 of the two .gz, which the Worker checks and caches by
set -eu
cd "$(dirname "$0")/../.."
ZIG=${ZIG:-.toolchain/zig}
OUT=${WEB_ZIGC_OUT:-web/zigc/build}
: "${ZIG_WASM:?set ZIG_WASM to zig.wasm (Zig 0.17.0 for wasm32-wasi)}"
[ -f "$ZIG_WASM" ] || { echo "no zig.wasm at $ZIG_WASM" >&2; exit 1; }
[ -x "$ZIG" ] || { echo "no Zig at $ZIG: run make zig (tools/get-zig.sh)" >&2; exit 1; }

sha256() { if command -v shasum >/dev/null; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
size() { wc -c < "$1" | tr -d ' '; }

LIB_DIR=$("$ZIG" env | sed -n 's/^ *\.lib_dir = "\(.*\)",$/\1/p')
VERSION=$("$ZIG" env | sed -n 's/^ *\.version = "\(.*\)",$/\1/p')
[ "$VERSION" = 0.17.0 ] || { echo "the bundle must come from Zig 0.17.0's lib (got $VERSION)" >&2; exit 1; }

mkdir -p "$OUT"
rm -rf "$OUT/support"
"$ZIG" run -OReleaseSafe web/zigc/bundle.zig -- "$LIB_DIR" "$OUT/zig-lib.bin"
gzip -9n -c "$OUT/zig-lib.bin" > "$OUT/zig-lib.bin.gz"
rm -f "$OUT/zig-lib.bin"
gzip -9n -c "$ZIG_WASM" > "$OUT/zig.wasm.gz"

# The files every compile needs besides the theme: [path the compile sees, path in the repo].
support='theme/argus_theme_sdk.zig:themes/argus_theme_sdk.zig
theme/argus_kernel.zig:themes/cpu/argus_kernel.zig
web/wasm/runtime.zig:web/wasm/runtime.zig
web/wasm/wasm_heap.zig:web/wasm/wasm_heap.zig
web/zigc/root.zig:web/zigc/root.zig
src/harness_gates.zig:src/harness_gates.zig'
list=''
for pair in $support; do
    virt=${pair%%:*}; repo=${pair#*:}
    mkdir -p "$OUT/support/$(dirname "$virt")"
    cp "$repo" "$OUT/support/$virt"
    list="$list${list:+,}[\"$virt\",\"support/$virt\"]"
done

cat > "$OUT/manifest.json" <<EOF
{
  "zigVersion": "$VERSION",
  "zig": { "file": "zig.wasm.gz", "bytes": $(size "$ZIG_WASM"), "gzBytes": $(size "$OUT/zig.wasm.gz"), "sha256": "$(sha256 "$OUT/zig.wasm.gz")" },
  "lib": { "file": "zig-lib.bin.gz", "gzBytes": $(size "$OUT/zig-lib.bin.gz"), "sha256": "$(sha256 "$OUT/zig-lib.bin.gz")" },
  "support": [$list]
}
EOF
echo "web-zigc: $OUT: zig.wasm.gz $(size "$OUT/zig.wasm.gz") B, zig-lib.bin.gz $(size "$OUT/zig-lib.bin.gz") B"
