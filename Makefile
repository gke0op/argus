# Zig 0.17.0: ./.toolchain/zig if present (gitignored, e.g. a symlink), otherwise zig on PATH.
ZIG ?= $(shell if [ -x ./.toolchain/zig ]; then echo ./.toolchain/zig; else command -v zig; fi)
ZFLAGS = -O ReleaseFast -target aarch64-macos -lc
THEME ?= themes/Echo.zig
FRAMES ?= 120
OUT ?= /tmp/argus_theme_out.png

.PHONY: all app desktop kronos harness claims test run stop clean gpu-bench

all: app kronos

desktop:
	$(ZIG) build-exe $(ZFLAGS) src/desktop_wallpaper.zig -femit-bin=argus-desktop

app: desktop
	mkdir -p Argus.app/Contents/MacOS
	cp argus-desktop Argus.app/Contents/MacOS/Argus
	chmod +x Argus.app/Contents/MacOS/Argus
	codesign --force --deep --sign - Argus.app 2>/dev/null || true

kronos:
	$(ZIG) build-exe $(ZFLAGS) src/kronos_tui.zig -femit-bin=kronos-tui

harness:
	$(ZIG) run $(ZFLAGS) src/theme_harness.zig -- $(THEME) --frames $(FRAMES) --out $(OUT)

claims:
	$(ZIG) run -lc -O ReleaseFast --dep theme -Mroot=src/claim_check.zig -O ReleaseFast -Mtheme=$(THEME)

test:
	$(ZIG) test $(ZFLAGS) src/desktop_wallpaper.zig
	$(ZIG) test $(ZFLAGS) src/kronos_tui.zig

run: app
	./Launch_Argus_Wallpaper.command

stop:
	./Stop_Argus_Wallpaper.command

clean:
	rm -rf argus-desktop kronos-tui Argus.app/Contents/MacOS .zig-cache zig-out *.o

# GPU prototype: Opus_Black_Hole's draw() as a Metal compute kernel, timed and diffed against the CPU.
GPU_FRAMES ?= 240
gpu-bench:
	$(ZIG) run -O ReleaseFast -target aarch64-macos -lc --dep theme -Mroot=src/gpu_bench.zig -O ReleaseFast -Mtheme=themes/Opus_Black_Hole.zig -- --frames $(GPU_FRAMES)
