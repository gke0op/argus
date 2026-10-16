#!/bin/bash
# Runs the headless theme harness on every git-tracked theme in themes/ (the shipped lineup; --all
# adds untracked local themes): the CPU harness on each .zig theme, the GPU harness on each .metal.
#   tools/check_themes.sh [--frames N] [--cpu-only | --gpu-only] [--no-budget] [--all]
# GPU checks are skipped (and say so) when this machine has no usable Metal device, as on some
# virtualized CI runners; set ARGUS_REQUIRE_GPU=1 to make that an error instead. --no-budget keeps
# frame time out of the verdict (shared CI runners are far slower than a Mac at a desk).
set -u
cd "$(dirname "$0")/.."
ZIG="${ZIG:-$( [ -x ./.toolchain/zig ] && echo ./.toolchain/zig || command -v zig )}"
export ZIG
FRAMES=120; CPU=1; GPU=1; ALL=0; EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --frames) FRAMES="${2:?--frames needs a number}"; shift ;;
        --cpu-only) GPU=0 ;;
        --gpu-only) CPU=0 ;;
        --no-budget) EXTRA+=(--no-budget) ;;
        --all) ALL=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
OUT_DIR="${TMPDIR:-/tmp}/argus_check_themes"
mkdir -p "$OUT_DIR" .zig-cache
HARNESS=.zig-cache/argus_theme_harness
"$ZIG" build-exe -O ReleaseFast -target aarch64-macos -lc src/theme_harness.zig -femit-bin="$HARNESS" || exit 1

themes() { # themes/*.$1: tracked files, or everything with --all (minus the SDK)
    if [ "$ALL" = 1 ]; then ls themes/*."$1" 2>/dev/null; else git ls-files "themes/*.$1"; fi | grep -v '/argus_theme_sdk\.zig$'
}

fail=0; passed=0; skipped=0
run() {
    local theme="$1" name log
    name="$(basename "$theme")"
    log="$OUT_DIR/$name.log"
    if "$HARNESS" "$theme" --frames "$FRAMES" --out "$OUT_DIR/$name.png" ${EXTRA[@]+"${EXTRA[@]}"} >"$log" 2>&1; then
        echo "PASS  $theme  ($(grep -m1 -E 'Avg (Frame|GPU Frame)' "$log" | sed 's/^ *//'))"
        passed=$((passed + 1))
    else
        echo "FAIL  $theme"; sed 's/^/      /' "$log"
        fail=$((fail + 1))
    fi
}

if [ "$CPU" = 1 ]; then
    for t in $(themes zig); do run "$t"; done
fi

if [ "$GPU" = 0 ]; then
    :
elif "$HARNESS" --probe-metal; then
    for t in $(themes metal); do run "$t"; done
else
    n=$(themes metal | wc -l | tr -d ' ')
    if [ "${ARGUS_REQUIRE_GPU:-0}" = "1" ]; then
        echo "FAIL  no Metal device: $n GPU themes not checked"; fail=$((fail + 1))
    else
        echo "SKIP  no Metal device on this machine: $n .metal themes not checked"
        skipped=$n
    fi
fi

echo "themes: $passed passed, $fail failed, $skipped skipped"
[ "$fail" -eq 0 ]
