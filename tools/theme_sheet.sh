#!/bin/sh
# tools/theme_sheet.sh: the render loop's contact sheet for a theme.
#
#   tools/theme_sheet.sh themes/My_Theme.metal [out_dir]      (or a .zig theme)
#
# Renders the theme at several moments (MOMENTS, in harness frames: 1/30 s each for Metal,
# one dt = 0.008 step each for Zig) and, for Metal themes, with several seeds (SEEDS, at
# the SEED_AT moment; Zig themes own their seeding). It cuts a 1:1 crop from the middle of
# the last moment and measures flicker: the share of pixels that jump more than 16% between
# two consecutive frames (FLICKER_AT and the next). Flicker includes real motion (a bright
# object moving a few pixels): find out what yours is made of before calling it shimmer. Everything lands in out_dir, plus
# sheet.png tiling it all when ImageMagick is installed.
#
# Look at every image. The harness verdict says the theme runs; this says how it looks
# from the first second to the ninetieth, and whether one seed's composition is a fluke.
set -eu

THEME=${1:?usage: tools/theme_sheet.sh themes/X.metal [out_dir]}
NAME=$(basename "$THEME")
NAME=${NAME%.*}
OUT=${2:-/tmp/argus_sheet_$NAME}
MOMENTS=${MOMENTS:-"2 150 900 2700"}
case "$THEME" in *.metal) SEEDS=${SEEDS-"1 7 42"} ;; *) SEEDS="" ;; esac
SEED_AT=${SEED_AT:-900}
FLICKER_AT=${FLICKER_AT:-900}
CROP=${CROP:-960x600+480+300}   # the 1:1 crop, WxH+X+Y in pixels of the 1920x1200 frame
mkdir -p "$OUT"

render() { # frames seed png
    # Short runs fail the budget gate (the first frame includes init): only the image counts here.
    rm -f "$3"
    make -s harness THEME="$THEME" FRAMES="$1" SEED="$2" OUT="$3" > "$3.log" 2>&1 || true
    if [ ! -f "$3" ]; then
        echo "no image for frames=$1 seed=$2: see $3.log" >&2
        grep -E "FAIL|error" "$3.log" >&2 || true
    fi
}

for m in $MOMENTS; do
    echo "moment: frame $m"
    render "$m" 0x5EED "$OUT/t$(printf %05d "$m").png"
done
for s in $SEEDS; do
    echo "seed: $s at frame $SEED_AT"
    render "$SEED_AT" "$s" "$OUT/seed_$s.png"
done
NEXT=$((FLICKER_AT + 1))
render "$FLICKER_AT" 0x5EED "$OUT/flicker_a.png"
render "$NEXT" 0x5EED "$OUT/flicker_b.png"

grep -E "Profile|Paced|Verdict" "$OUT/flicker_a.png.log" || true

if command -v magick > /dev/null 2>&1; then
    LAST=$(ls "$OUT"/t*.png | tail -1)
    magick "$LAST" -crop "$CROP" +repage "$OUT/crop_1to1.png"
    PX=$(magick compare -metric AE -fuzz 16% "$OUT/flicker_a.png" "$OUT/flicker_b.png" null: 2>&1 | awk '{print $1}')
    echo "flicker: $PX px of 2304000 jump >16% between frames $FLICKER_AT and $NEXT" \
        "($(echo "$PX" | awk '{printf "%.2f", 100*$1/2304000}')%)"
    # Row 1 is MOMENTS in order, row 2 is SEEDS in order (unlabelled: labels need Ghostscript).
    magick -background '#111' "$OUT"/t*.png -resize 480x300 -bordercolor '#111' -border 4 +append +repage "$OUT/sheet.png"
    if [ -n "$SEEDS" ]; then
        magick -background '#111' "$OUT"/seed_*.png -resize 480x300 -bordercolor '#111' -border 4 +append "$OUT/seeds.png"
        magick -background '#111' "$OUT/sheet.png" "$OUT/seeds.png" -gravity west -append +repage "$OUT/sheet.png"
    fi
    echo "sheet: $OUT/sheet.png (row 1: frames $MOMENTS; row 2: seeds $SEEDS)"
    echo "crop:  $OUT/crop_1to1.png"
else
    echo "ImageMagick not found: look at the PNGs in $OUT one by one."
fi
