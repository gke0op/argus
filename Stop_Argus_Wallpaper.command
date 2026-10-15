#!/bin/zsh
pkill -f "Argus.app/Contents/MacOS/Argus" 2>/dev/null || true
pkill -f "argus-desktop" 2>/dev/null || true
echo "Stopped Argus.app."
