# Zig 0.17.0: ./.toolchain/zig if present (gitignored; `make zig` installs it), otherwise zig on PATH.
ZIG ?= $(shell if [ -x ./.toolchain/zig ]; then echo ./.toolchain/zig; else command -v zig; fi)
# Off macOS (a Linux VM) only `make harness` on .zig themes works: it builds for this machine.
ZFLAGS = -O ReleaseFast -target $(if $(filter Darwin,$(shell uname -s)),aarch64-macos,native) -lc
THEME ?= themes/Cygnus_A.zig
FRAMES ?= 120
OUT ?= /tmp/argus_theme_out.png

.PHONY: icon quasars all app desktop kronos harness linux web-wasm web-wasm-all web-wasm-refs web-wasm-serve web-zigc web-zigc-test check-themes claims ledger test run stop clean zig release gpu-bench gpu-probes metalfx-demo gpu-arch social

all: app kronos

desktop:
	$(ZIG) build-exe $(ZFLAGS) src/desktop_wallpaper.zig -femit-bin=argus-desktop

# Code-signing identity for `make app`: ad-hoc (-) unless SIGN is given or .sign_identity (one line,
# gitignored) names one. macOS ties privacy permissions (Desktop folder access) to the signature;
# an ad-hoc signature changes with every build, so it asks again after each rebuild. A stable
# identity, even a self-signed one from Keychain Access, keeps the permission. Releases stay ad-hoc.
SIGN ?= $(or $(shell cat .sign_identity 2>/dev/null),-)

app: desktop
	mkdir -p Argus.app/Contents/MacOS
	cp argus-desktop Argus.app/Contents/MacOS/Argus
	chmod +x Argus.app/Contents/MacOS/Argus
	@if [ "$(SIGN)" = "-" ]; then codesign --force --deep --sign - Argus.app 2>/dev/null || true; \
	else echo "codesign: $(SIGN)"; codesign --force --deep --sign "$(SIGN)" Argus.app; fi

kronos:
	$(ZIG) build-exe $(ZFLAGS) src/kronos_tui.zig -femit-bin=kronos-tui

harness:
	$(ZIG) run $(ZFLAGS) src/theme_harness.zig -- $(THEME) --frames $(FRAMES) --out $(OUT) $(if $(SEED),--seed $(SEED)) $(if $(FPS),--fps $(FPS)) $(if $(STATS),--stats $(STATS)) $(if $(DATE),--date $(DATE))

# Linux X11 live wallpaper (pure Zig, no libc): THEME is compiled in. ./argus-linux to run.
# -fstrip: debug info is most of the LLVM time (rebuild 20 s -> 6 s) and size (4.7 MB -> 324 KB).
# CPU=x86_64_v3 for a binary to hand out (AVX2; plain x86_64 is ~8x slower on kernel themes).
CPU ?= native
linux:
	$(ZIG) build-exe -O ReleaseFast -fstrip -mcpu=$(CPU) --dep theme -Mroot=src/argus_linux.zig -Mtheme=$(THEME) -femit-bin=argus-linux

# Browser (web/wasm/README.md): THEME compiled to WebAssembly with SIMD128, the same source the
# harness builds, twice: NAME.mt.wasm (+atomics, shared memory: a page's Worker pool runs it on
# every core) and NAME.st.wasm (one thread, for pages without cross-origin isolation).
WEB_WASM_OUT ?= web/wasm/build
WASM_FLAGS = -O ReleaseFast -target wasm32-freestanding -fno-entry -rdynamic -fstrip \
	--import-memory --initial-memory=4194304 --max-memory=1073741824 \
	--dep theme --dep harness_gates -Mroot=web/wasm/runtime.zig -Mtheme=$(THEME) -Mharness_gates=src/harness_gates.zig
web-wasm:
	@mkdir -p $(WEB_WASM_OUT)
	@# Gate 1 as the native harness sees it: on wasm32 usize is 32 bits, so `const x: u32 = n_usize;`
	@# compiles there and fails on aarch64-macos. Type-check for the app's target first.
	$(ZIG) build-lib -dynamic -lc -fno-emit-bin -O ReleaseFast -target aarch64-macos $(THEME)
	$(ZIG) build-exe -mcpu=generic+simd128+atomics+bulk_memory -fno-single-threaded --shared-memory $(WASM_FLAGS) -femit-bin=$(WEB_WASM_OUT)/$(basename $(notdir $(THEME))).mt.wasm
	$(ZIG) build-exe -mcpu=generic+simd128 -fsingle-threaded $(WASM_FLAGS) -femit-bin=$(WEB_WASM_OUT)/$(basename $(notdir $(THEME))).st.wasm

# Every theme the dev page lists, the BENCHMARK.md skeleton and the gate fixtures. A theme that
# fails to compile is recorded (Gate 1) in build/NAME.compile.txt, not fatal. Then the manifest.
WEB_WASM_THEMES ?= themes/cpu/Tutorial_Tides.zig themes/Cygnus_A.zig tests/fixtures/Fixture_Stateful.zig tests/fixtures/Fixture_Stateless.zig tests/fixtures/Fixture_Hang.zig $(sort $(wildcard tests/fixtures/Gate*.zig))
web-wasm-all:
	@mkdir -p $(WEB_WASM_OUT)/stage
	@awk '/^### Minimal Working Skeleton/{s=1} s&&/^```zig/{c=1;next} c&&/^```/{exit} c' BENCHMARK.md > $(WEB_WASM_OUT)/stage/Bench_Skeleton.zig
	@cp themes/argus_theme_sdk.zig $(WEB_WASM_OUT)/stage/argus_theme_sdk.zig
	@for t in $(WEB_WASM_THEMES) $(WEB_WASM_OUT)/stage/Bench_Skeleton.zig; do \
		n=$$(basename $$t .zig); \
		if $(MAKE) -s web-wasm THEME=$$t > $(WEB_WASM_OUT)/$$n.compile.txt 2>&1; then echo "  ok    $$n"; else echo "  FAIL  $$n (Gate 1: compile; see $(WEB_WASM_OUT)/$$n.compile.txt)"; fi; \
	done
	@cd $(WEB_WASM_OUT) && { printf '['; sep=''; for f in *.compile.txt; do n=$${f%.compile.txt}; \
		if [ -f $$n.st.wasm ]; then ok=true; else ok=false; fi; \
		printf '%s{"name":"%s","compiled":%s}' "$$sep" "$$n" "$$ok"; sep=','; done; printf ']\n'; } > manifest.json

# Native harness reports and final frames for the dev page's comparison (build/NAME.native.*).
# Fixture_Hang is left out: the native harness has no time limit and would never return.
web-wasm-refs: web-wasm-all
	@for t in $(filter-out tests/fixtures/Fixture_Hang.zig,$(WEB_WASM_THEMES)) $(WEB_WASM_OUT)/stage/Bench_Skeleton.zig; do \
		n=$$(basename $$t .zig); \
		$(ZIG) run $(ZFLAGS) src/theme_harness.zig -- $$t --frames 120 --out $(WEB_WASM_OUT)/$$n.native.png > $(WEB_WASM_OUT)/$$n.native.txt 2>&1; \
		echo "  native $$n: $$(grep -o 'Verdict *: [A-Z]*' $(WEB_WASM_OUT)/$$n.native.txt || echo 'did not compile')"; \
	done

# The bench page's in-browser compiler (web/zigc/README.md): zig.wasm (Zig 0.17.0 for wasm32-wasi;
# .github/workflows/pages.yml builds it from the official source tarball) and the std import
# closure of the release's lib, into web/zigc/build/. web-zigc-test compiles and grades the gate
# fixtures, the BENCHMARK.md skeleton and Tutorial_Tides with it in Node.
ZIG_WASM ?=
web-zigc:
	ZIG="$(ZIG)" ZIG_WASM="$(ZIG_WASM)" web/zigc/build.sh
web-zigc-test:
	node web/zigc/test.mjs --pathological --zig "$(ZIG_WASM)" --lib "$$($(ZIG) env | sed -n 's/^ *\.lib_dir = "\(.*\)",$$/\1/p')"

# The dev page needs cross-origin isolation for threads; this server sends the COOP/COEP headers
# (GitHub Pages cannot; there coi-serviceworker.js adds them, see web/wasm/README.md).
web-wasm-serve:
	node web/wasm/serve.mjs

# The harness on every tracked theme: CPU for each .zig, GPU for each .metal (skipped without a
# Metal device). tools/check_themes.sh --all also checks untracked local themes.
check-themes:
	ZIG=$(ZIG) tools/check_themes.sh --frames $(FRAMES) $(CHECK_ARGS)

claims:
	$(ZIG) run -lc -O ReleaseFast --dep theme -Mroot=src/claim_check.zig -O ReleaseFast -Mtheme=$(THEME)

# Test ledger: one JSON record per checked physics claim, from the theme's tests, claims and gpu-bench.
LEDGER_THEME ?= themes/Cygnus_A.zig
LEDGER_OUT ?= docs/cygnus_a_ledger.json
ledger:
	ZIG=$(ZIG) tools/ledger.sh $(LEDGER_THEME) $(LEDGER_OUT)

# Argus.app's icon (Contents/Resources/Argus.icns, committed): the Cygnus A still in the macOS
# icon shape. Needs Pillow.
icon:
	python3 -I tools/app_icon.py

# Quasar themes: generated from tools/quasar_template.zig by tools/gen_quasars.py (Cygnus_A, plus
# any local configurations in tools/local/*.json, which stay untracked).
quasars:
	python3 -I tools/gen_quasars.py

# Vertical social videos (tools/social/README.md): offline theme renders on a drawn Mac screen,
# Space swipes (FORMAT=pov) or a camera move in a Kerr theme's simulation (FORMAT=orbit), hook, end card. HOOK and NAME take
# variants separated by |.
FORMAT ?= pov
THEMES ?= Cygnus_A,Night_Tide,Roulette_Chrome,Phosphor_Terminal
HOOK ?= POV: every desktop on your Mac is a different universe
SOCIAL_OUT ?= $(HOME)/Desktop/argus-clips/social
social:
	ZIG=$(ZIG) python3 -I tools/social/social.py --format $(FORMAT) --themes $(THEMES) --out "$(SOCIAL_OUT)" \
		--hook "$(HOOK)" $(if $(NAME),--name "$(NAME)") \
		$(if $(SOUND),--sound "$(SOUND)") $(if $(SEG),--seg $(SEG)) $(if $(CLOCK),--clock $(CLOCK)) $(if $(STILLS),--stills $(STILLS))

test:
	python3 -I tools/gen_quasars.py --check
ifeq ($(shell uname -s),Darwin)
	$(ZIG) test $(ZFLAGS) src/desktop_wallpaper.zig
	$(ZIG) test $(ZFLAGS) src/kronos_tui.zig
	$(ZIG) test $(ZFLAGS) themes/cpu/argus_kernel.zig
else
	# Linux: the app is macOS-only, so its tests are compiled for macOS (type-checked, not run);
	# Kronos and the CPU kernel run here, the kernel also as aarch64 under qemu when installed
	# (the 4-lane NEON path Apple silicon takes).
	$(ZIG) test -target aarch64-macos -lc --test-no-exec -femit-bin=.zig-cache/test_app_macos src/desktop_wallpaper.zig
	$(ZIG) test $(ZFLAGS) src/kronos_tui.zig
	$(ZIG) test $(ZFLAGS) themes/cpu/argus_kernel.zig
	if command -v qemu-aarch64-static >/dev/null; then $(ZIG) test -target aarch64-linux themes/cpu/argus_kernel.zig --test-cmd qemu-aarch64-static --test-cmd-bin; fi
endif

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
VERSION ?= 0.1.8
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
	@# The theme-authoring skills: .claude/skills/ so Claude Code finds them in the unzipped folder,
	@# plus a visible WRITING_THEMES.md that points people and other agents to them.
	mkdir -p $(STAGE)/.claude && tar -c $$(git ls-files .claude/skills) | tar -x -C $(STAGE)
	cp docs/WRITING_THEMES.md $(STAGE)/WRITING_THEMES.md
	cp NOTE.md $(STAGE)/NOTE.md
	@# The download's own agent map (the repository's AGENTS.md describes the source tree).
	cp docs/AGENTS_DOWNLOAD.md $(STAGE)/AGENTS.md
	printf '@AGENTS.md\n' > $(STAGE)/CLAUDE.md
	for t in $$(git ls-files 'themes/*.zig'); do \
		[ "$$(basename $$t)" = argus_theme_sdk.zig ] && continue; \
		./argus-desktop --precompile $(STAGE)/$$t $(STAGE)/Argus.app/Contents/Resources/prebuilt || exit 1; \
	done
	codesign --force --deep --sign - $(STAGE)/Argus.app
	codesign --verify --deep --strict $(STAGE)/Argus.app
	cd dist && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent $(RELEASE) $(RELEASE).zip
	@cd dist && shasum -a 256 $(RELEASE).zip | tee $(RELEASE).zip.sha256
	@du -h dist/$(RELEASE).zip

# GPU prototype: a Kerr-disk theme's draw() as a Metal compute kernel, timed and diffed against the CPU.
GPU_FRAMES ?= 240
BH_THEME ?= themes/Cygnus_A.zig # any theme on the Kerr-disk engine
metalfx-demo:
	$(ZIG) run $(ZFLAGS) src/metalfx_demo.zig -- $(THEME) --out-dir $(dir $(OUT))

ARCH ?= all
gpu-arch:
	$(ZIG) run $(ZFLAGS) src/gpu_arch_probe.zig -- $(ARCH)

gpu-probes:
	tools/gpu_probes/run.sh

gpu-bench:
	$(ZIG) run -O ReleaseFast -target aarch64-macos -lc --dep theme -Mroot=src/gpu_bench.zig -O ReleaseFast -Mtheme=$(BH_THEME) -- --frames $(GPU_FRAMES)
