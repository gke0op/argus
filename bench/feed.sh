#!/bin/sh
# bench/feed.sh OUT_DIR: the live board's feed, OUT_DIR/feed.json (bench/feed.zig says what is in it).
#
#   REPO=gke0op/argus bench/feed.sh /tmp/feed      # needs gh (authenticated), jq and .toolchain/zig
#
# Reads the 100 most recently updated pull requests; for each that adds or changes a file under
# bench/submissions/, its files and its comments. Only reads: it never checks out or runs a
# pull request's code. .github/workflows/bench-feed.yml runs it and publishes the result.
set -eu
REPO=${REPO:-gke0op/argus}
ZIG=${ZIG:-.toolchain/zig}
out=${1:?usage: bench/feed.sh OUT_DIR}
mkdir -p "$out/in"
rm -f "$out"/in/*.json

gh api "repos/$REPO/pulls?state=all&per_page=100&sort=updated&direction=desc" > "$out/in/pulls.json"
for n in $(jq -r '.[].number' "$out/in/pulls.json"); do
    case "$n" in (*[!0-9]*|'') continue ;; esac
    gh api --paginate "repos/$REPO/pulls/$n/files?per_page=100" | jq -s 'add // []' > "$out/in/files-$n.json"
    if jq -e 'any(.[]; (.filename | startswith("bench/submissions/")) and (.filename | endswith(".zig")))' "$out/in/files-$n.json" > /dev/null; then
        gh api --paginate "repos/$REPO/issues/$n/comments?per_page=100" | jq -s 'add // []' > "$out/in/comments-$n.json"
    else
        rm -f "$out/in/files-$n.json"
    fi
done
"$ZIG" run -OReleaseSafe bench/feed.zig -- "$out/in" "$REPO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$out/feed.json"
echo "feed: $(jq '.entries | length' "$out/feed.json") entries -> $out/feed.json"
