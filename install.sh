#!/bin/sh
# Installs (or updates) Argus from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/gke0op/argus/main/install.sh | sh
#
# Downloads the release zip, checks it against the release's SHA-256, puts the folder at
# ~/Applications/Argus and opens Argus.app. Run it again to update: your settings
# (.argus_spaces.conf, .argus_settings.conf) and your own themes stay; a shipped theme you
# edited is kept as <name>.before-<version> next to the new one.
#
# ARGUS_DIR=<folder>   install somewhere else
# ARGUS_VERSION=0.1.4  a specific release instead of the latest
# ARGUS_NO_OPEN=1      don't open the app afterwards
set -eu

REPO=gke0op/argus
DEST=${ARGUS_DIR:-$HOME/Applications/Argus}

die() { printf 'argus install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Argus runs on macOS only."
[ "$(uname -m)" = arm64 ] || die "Argus needs a Mac with Apple silicon (arm64)."

if [ -n "${ARGUS_VERSION:-}" ]; then
    tag=v${ARGUS_VERSION#v}
else
    tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") ||
        die "could not reach GitHub."
    tag=${tag##*/}
fi
case $tag in v[0-9]*) ;; *) die "could not find the latest release." ;; esac

name=Argus-$tag-macos-arm64
base=https://github.com/$REPO/releases/download/$tag
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "Downloading Argus $tag..."
curl -fL --progress-bar -o "$tmp/$name.zip" "$base/$name.zip" || die "download failed ($base/$name.zip)."
curl -fsSL -o "$tmp/$name.zip.sha256" "$base/$name.zip.sha256" || die "could not download the checksum."
(cd "$tmp" && shasum -a 256 -c "$name.zip.sha256" >/dev/null 2>&1) ||
    die "the download does not match the release's SHA-256. Nothing was installed."
ditto -x -k "$tmp/$name.zip" "$tmp/x"
src=$tmp/x/$name
[ -d "$src/Argus.app" ] || die "unexpected archive layout. Nothing was installed."

# Updating: quit the Argus running from this folder (only that one), and keep edited themes.
if [ -d "$DEST/Argus.app" ]; then
    bin=$DEST/Argus.app/Contents/MacOS/Argus
    pids=$(pgrep -f "^$bin" || true)
    if [ -n "$pids" ]; then
        echo "Quitting the running Argus..."
        # shellcheck disable=SC2086 # one argument per pid
        kill $pids 2>/dev/null || true
        i=0
        while pgrep -f "^$bin" >/dev/null 2>&1 && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
    fi
    for f in "$src"/themes/*; do
        old=$DEST/themes/${f##*/}
        if [ -f "$old" ] && ! cmp -s "$f" "$old"; then
            cp -p "$old" "$old.before-$tag"
            echo "themes/${f##*/} differed from $tag's; your copy is now themes/${f##*/}.before-$tag"
        fi
    done
    rm -rf "$DEST/Argus.app"
fi

mkdir -p "$DEST"
ditto "$src" "$DEST"
echo "Argus $tag is in $DEST"

if [ -z "${ARGUS_NO_OPEN:-}" ]; then
    open "$DEST/Argus.app"
    echo "Click the eye in the menu bar to pick a theme for each Desktop Space."
fi
