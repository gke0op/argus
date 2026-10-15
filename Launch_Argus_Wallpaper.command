#!/bin/zsh
cd "$(dirname "$0")"
if [ ! -f ./Argus.app/Contents/MacOS/Argus ]; then
    make app
fi
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
open -n ./Argus.app 2>/dev/null || (nohup ./Argus.app/Contents/MacOS/Argus >/dev/null 2>&1 </dev/null &)
echo "========================================================================"
echo " ARGUS.APP // BARE-METAL MACOS MULTI-SPACE LIVE WALLPAPER ENGINE"
echo "   Menu Bar    : Click the eye in your top macOS Menu Bar"
echo "   App Bundle  : $(pwd)/Argus.app"
echo "   To stop     : Click 'Quit' in the Menu Bar popover or run the Stop script"
echo "========================================================================"
