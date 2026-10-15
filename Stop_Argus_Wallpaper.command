#!/bin/zsh
# Ask every running Argus to quit, wait for it to exit (it restores state on the way out),
# and only force-kill a copy that is still alive after 5 s, so two copies never overlap.
pkill -f "Argus.app/Contents/MacOS/Argus" 2>/dev/null || true
pkill -f "argus-desktop" 2>/dev/null || true
for _ in {1..50}; do
    pgrep -f "Argus.app/Contents/MacOS/Argus|argus-desktop" >/dev/null || break
    sleep 0.1
done
pkill -9 -f "Argus.app/Contents/MacOS/Argus" 2>/dev/null || true
pkill -9 -f "argus-desktop" 2>/dev/null || true
echo "Stopped Argus.app."
