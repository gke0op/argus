#!/bin/zsh
cd "$(dirname "$0")"
if [ ! -f ./Argus.app/Contents/MacOS/Argus ]; then
    make app
fi
pkill -f "Argus.app/Contents/MacOS/Argus" 2>/dev/null || true
pkill -f "argus-desktop" 2>/dev/null || true
sleep 0.15
open -n ./Argus.app 2>/dev/null || (nohup ./Argus.app/Contents/MacOS/Argus >/dev/null 2>&1 </dev/null &)
echo "========================================================================"
echo " ARGUS.APP // BARE-METAL MACOS MULTI-SPACE LIVE WALLPAPER ENGINE"
echo "   Menu Bar    : Click '✦ Argus X/8' in your top macOS Menu Bar!"
echo "   App Bundle  : $(pwd)/Argus.app"
echo "   Window Layer: kCGDesktopWindowLevel + 1 (Per-Space Aware, Click-Through)"
echo "   To stop     : Click 'Quit' in Menu Bar Popover or run Stop script"
echo "========================================================================"
