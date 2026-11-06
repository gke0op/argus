#!/bin/sh
# site/build.sh [OUT]: assemble the public site (GitHub Pages) into OUT, default _site/.
#
#   site/build.sh              # from the repo root or anywhere; needs .toolchain/zig (make zig)
#   node web/wasm/serve.mjs --no-isolation --root _site    # or any static server
#
# What goes in:
#   site/*            the pages and assets (HTML filled from BENCHMARK.md by site/tools/render.zig)
#   web/              the three engines, every tracked file, at /web/ (their relative URLs hold)
#   web/wasm/build/   the wasm builds (make web-wasm-all, run here if missing)
#   coi-serviceworker.js at the root, so its scope covers every page
#   BENCHMARK.md, web/README.md: the bench page copies them into a model's prompt
set -eu
cd "$(dirname "$0")/.."
OUT=${1:-_site}
ZIG=${ZIG:-.toolchain/zig}

[ -x "$ZIG" ] || { echo "no Zig at $ZIG: run make zig (tools/get-zig.sh)" >&2; exit 1; }
if [ ! -f web/wasm/build/manifest.json ] || [ "${REBUILD_WASM:-0}" = 1 ]; then
    make -s web-wasm-all ZIG="$ZIG"
fi

# Empty OUT in place (a local server holding the folder keeps serving the new files).
mkdir -p "$OUT"
find "$OUT" -mindepth 1 -delete

# Pages and assets: everything in site/ but the build tooling.
(cd site && find . -type f ! -path './tools/*' ! -name build.sh ! -name README.md) | while read -r f; do
    mkdir -p "$OUT/$(dirname "$f")"
    case "$f" in
        *.html) "$ZIG" run site/tools/render.zig -- BENCHMARK.md "site/$f" "$OUT/$f" ;;
        *) cp "site/$f" "$OUT/$f" ;;
    esac
done

# The engines, as tracked in git (no local scratch), and the wasm builds.
git ls-files web | while read -r f; do
    mkdir -p "$OUT/$(dirname "$f")"
    cp "$f" "$OUT/$f"
done
mkdir -p "$OUT/web/wasm/build"
cp web/wasm/build/*.wasm web/wasm/build/*.compile.txt web/wasm/build/manifest.json "$OUT/web/wasm/build/"

# The bench page's in-browser compiler (make web-zigc ZIG_WASM=...; CI builds zig.wasm). Without
# it the page still grades prebuilt and uploaded builds; REQUIRE_ZIGC=1 (CI) makes it an error.
if [ -f web/zigc/build/manifest.json ]; then
    mkdir -p "$OUT/web/zigc"
    cp -R web/zigc/build "$OUT/web/zigc/build"
elif [ "${REQUIRE_ZIGC:-0}" = 1 ]; then
    echo "site: web/zigc/build is missing (make web-zigc ZIG_WASM=...)" >&2; exit 1
else
    echo "site: no web/zigc/build: the bench page cannot compile Zig (make web-zigc ZIG_WASM=...)" >&2
fi

# The Zig sources of the bench page's prebuilt builds, to read next to their verdicts.
mkdir -p "$OUT/bench/zig"
cp tests/fixtures/Gate*.zig tests/fixtures/Fixture_*.zig web/wasm/build/stage/Bench_Skeleton.zig "$OUT/bench/zig/"
cp themes/cpu/Tutorial_Tides.zig "$OUT/bench/zig/Tutorial_Tides.zig"

cp web/wasm/coi-serviceworker.js "$OUT/coi-serviceworker.js"
cp BENCHMARK.md "$OUT/BENCHMARK.md"
cp docs/media/social-card.png "$OUT/assets/social-card.png"
touch "$OUT/.nojekyll"   # serve files as they are (no Jekyll pass on Pages)

echo "site: $OUT ($(du -sh "$OUT" | cut -f1), $(find "$OUT" -type f | wc -l | tr -d ' ') files)"
