#!/bin/sh
# ARGUS-BENCH test ledger: collects every `LEDGER {json}` record printed by a Kerr-disk theme's
# tests, `make claims` and `make gpu-bench` into one JSON file, with the commit, the runs and
# their exit codes. One record per checked claim: claim, reference, conditions, quantity,
# measured, bounds [lo, hi], pass (null = reported, not asserted), source.
#
#   tools/ledger.sh [THEME] [OUT]     (make ledger)
#
# Exits non-zero if any run failed or any asserted record failed; the file is written anyway.
set -u
THEME=${1:-themes/H1821.zig}
OUT=${2:-docs/h1821_ledger.json}
ZIG=${ZIG:-$(if [ -x ./.toolchain/zig ]; then echo ./.toolchain/zig; else command -v zig; fi)}
GPU_FRAMES=${GPU_FRAMES:-30}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

runs=""
status=0
run() { # name, command...
    name=$1
    shift
    echo "ledger: $*" >&2
    "$@" >"$tmp/$name.log" 2>&1
    code=$?
    [ $code -eq 0 ] || status=1
    [ $code -eq 0 ] || echo "ledger: exit $code (log tail below)" >&2
    [ $code -eq 0 ] || grep -v '^LEDGER ' "$tmp/$name.log" | tail -5 >&2
    runs="$runs${runs:+,}{\"command\":\"$*\",\"exit\":$code}"
    sed -n 's/^LEDGER //p' "$tmp/$name.log" >>"$tmp/records"
}
: >"$tmp/records"
run test "$ZIG" test "$THEME"
run claims make -s claims THEME="$THEME" ZIG="$ZIG"
run gpu_bench make -s gpu-bench BH_THEME="$THEME" GPU_FRAMES="$GPU_FRAMES" ZIG="$ZIG"

n=$(wc -l <"$tmp/records" | tr -d ' ')
passed=$(grep -c '"pass":true' "$tmp/records")
failed=$(grep -c '"pass":false' "$tmp/records")
[ "$failed" -eq 0 ] || status=1
dirty=false
[ -z "$(git status --porcelain -- . ":(exclude)$OUT" 2>/dev/null)" ] || dirty=true
{
    printf '{\n"ledger":"ARGUS-BENCH test ledger","theme":"%s",\n' "$THEME"
    printf '"commit":"%s","dirty":%s,"generated":"%s",\n' "$(git rev-parse HEAD 2>/dev/null)" "$dirty" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '"runs":[%s],\n' "$runs"
    printf '"summary":{"records":%s,"asserted":%s,"passed":%s,"failed":%s},\n' "$n" $((passed + failed)) "$passed" "$failed"
    printf '"records":[\n'
    sed '$!s/$/,/' "$tmp/records"
    printf ']\n}\n'
} >"$OUT"
echo "ledger: $OUT: $n records, $passed passed, $failed failed, $((n - passed - failed)) reported" >&2
grep '"pass":false' "$tmp/records" | sed 's/^{"id":"\([^"]*\)".*"measured":\([^,]*\),"lo":\([^,]*\),"hi":\([^,]*\),.*/ledger: FAIL \1: measured \2, bounds [\3, \4]/' >&2
exit $status
