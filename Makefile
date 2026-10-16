# Zig 0.17.0: ./.toolchain/zig if present (gitignored; `make zig` installs it), otherwise zig on PATH.
ZIG ?= $(shell if [ -x ./.toolchain/zig ]; then echo ./.toolchain/zig; else command -v zig; fi)
ZFLAGS = -O ReleaseFast -target aarch64-macos -lc
THEME ?= themes/Echo.zig
FRAMES ?= 120
OUT ?= /tmp/argus_theme_out.png

.PHONY: quasars all app desktop kronos harness check-themes claims ledger test run stop clean zig release gpu-bench gpu-probes metalfx-demo gpu-arch

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

# The harness on every theme: CPU for each .zig, GPU for each .metal (skipped without a Metal device).
check-themes:
	ZIG=$(ZIG) tools/check_themes.sh --frames $(FRAMES)

claims:
	$(ZIG) run -lc -O ReleaseFast --dep theme -Mroot=src/claim_check.zig -O ReleaseFast -Mtheme=$(THEME)

# Test ledger: one JSON record per checked physics claim, from the theme's tests, claims and gpu-bench.
LEDGER_THEME ?= themes/Majestic_Glutton.zig
LEDGER_OUT ?= docs/majestic_glutton_ledger.json
ledger:
	ZIG=$(ZIG) tools/ledger.sh $(LEDGER_THEME) $(LEDGER_OUT)

# The quasar family: generated from themes/Majestic_Glutton.zig (tools/gen_quasars.py).
quasars:
	python3 -I tools/gen_quasars.py

test:
	python3 -I tools/gen_quasars.py --check
	$(ZIG) test $(ZFLAGS) src/desktop_wallpaper.zig
	$(ZIG) test $(ZFLAGS) src/kronos_tui.zig

run: app
	./Launch_Argus_Wallpaper.command

stop:
	./Stop_Argus_Wallpaper.command

clean:
	rm -rf argus-desktop kronos-tui Argus.app/Contents/MacOS .zig-cache zig-out *.o dist

# Installs the pinned Zig 0.17.0 into .toolchain/ (downloaded from ziglang.org, SHA-256 checked).
zig:
	tools/get-zig.sh

# A download for a GitHub Release: dist/Argus-v$(VERSION)-macos-arm64.zip holds one folder with
# Argus.app (ad-hoc signed) and the git-tracked files of themes/ (never a glob of the folder). Every .zig theme ships precompiled and verified in
# Argus.app/Contents/Resources/prebuilt, so the app runs them with no Zig installed; a theme
# that is edited or added later is compiled at runtime and needs Zig 0.17.0.
VERSION ?= 0.1.0
RELEASE = Argus-v$(VERSION)-macos-arm64
STAGE = dist/$(RELEASE)
release: app
	python3 -I tools/gen_quasars.py --check
	@# Only committed themes ship: an untracked or edited file under themes/ fails the release.
	@git diff --quiet HEAD -- themes && [ -z "$$(git ls-files --others --exclude-standard themes)" ] || \
		{ echo "release: themes/ has untracked or modified files; commit or move them first:"; git status --short --untracked-files=all themes; exit 1; }
	@[ "$(ALLOW_DIRTY)" = 1 ] || git diff --quiet HEAD -- src Argus.app docs/INSTALL.md || \
		{ echo "release: uncommitted changes in src/, Argus.app or docs/INSTALL.md (ALLOW_DIRTY=1 to build anyway)"; exit 1; }
	@grep -q "<string>$(VERSION)</string>" Argus.app/Contents/Info.plist || { echo "Info.plist CFBundleShortVersionString is not $(VERSION)"; exit 1; }
	rm -rf $(STAGE) dist/$(RELEASE).zip
	mkdir -p $(STAGE)
	cp -R Argus.app $(STAGE)/Argus.app
	rm -rf $(STAGE)/Argus.app/Contents/_CodeSignature
	tar -c $$(git ls-files themes) | tar -x -C $(STAGE)
	cp LICENSE NOTICE.md $(STAGE)/
	cp docs/INSTALL.md $(STAGE)/INSTALL.md
	for t in $$(git ls-files 'themes/*.zig'); do \
		[ "$$(basename $$t)" = argus_theme_sdk.zig ] && continue; \
		./argus-desktop --precompile $(STAGE)/$$t $(STAGE)/Argus.app/Contents/Resources/prebuilt || exit 1; \
	done
	codesign --force --deep --sign - $(STAGE)/Argus.app
	codesign --verify --deep --strict $(STAGE)/Argus.app
	cd dist && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent $(RELEASE) $(RELEASE).zip
	@cd dist && shasum -a 256 $(RELEASE).zip | tee $(RELEASE).zip.sha256
	@du -h dist/$(RELEASE).zip

# GPU prototype: Majestic Glutton's draw() as a Metal compute kernel, timed and diffed against the CPU.
GPU_FRAMES ?= 240
BH_THEME ?= themes/Majestic_Glutton.zig # any theme on the Kerr-disk engine (or themes/Gargantua.zig)
metalfx-demo:
	$(ZIG) run $(ZFLAGS) src/metalfx_demo.zig -- $(THEME) --out-dir $(dir $(OUT))

ARCH ?= all
gpu-arch:
	$(ZIG) run $(ZFLAGS) src/gpu_arch_probe.zig -- $(ARCH)

gpu-probes:
	tools/gpu_probes/run.sh

gpu-bench:
	$(ZIG) run -O ReleaseFast -target aarch64-macos -lc --dep theme -Mroot=src/gpu_bench.zig -O ReleaseFast -Mtheme=$(BH_THEME) -- --frames $(GPU_FRAMES)
