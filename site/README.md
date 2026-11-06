# site/: Argus's public website and the in-browser ARGUS-BENCH

Vanilla HTML, CSS and JavaScript (no framework, no npm), on top of the three engines in `web/`
(`web/README.md`, `web/cygnus/README.md`, `web/wasm/README.md`). GitHub Pages serves it from
`.github/workflows/pages.yml`.

| Path | What it is |
|---|---|
| `index.html` | Home: a live full-bleed theme (Cygnus A first) with a picker for the 10 shipped themes and Tides as wasm, telemetry, install, the leaderboard, how it works |
| `bench/index.html` | Run ARGUS-BENCH: the prompts to copy, then grading in the page (Zig as wasm through the 8 gates; WGSL on WebGPU through the Metal harness's checks) |
| `bench/fixtures/*.wgsl` | WGSL themes that each fail one check (the Zig gate fixtures are `tests/fixtures/`) |
| `assets/engines.js` | The theme list and `mount()`: any engine on a fresh canvas, sized to device pixels, on rAF |
| `assets/home.js`, `assets/bench.js`, `assets/ui.js` | The pages' scripts |
| `assets/wgsl-harness.js` | `src/theme_harness.zig`'s Metal harness, on WebGPU |
| `tools/render.zig` | Fills the leaderboard table and the zero-shot prompt into the HTML from `BENCHMARK.md` |
| `tools/serve.zig` | A local server that mounts the site under `/argus/` with no COOP/COEP, as Pages does |
| `tools/check.mjs` | Headless Chrome check: load size, time to first frame, every theme, the bench verdicts, phone width, no-WebGPU fallback |
| `build.sh` | Assembles `_site/`: the pages, `web/`, the wasm builds, `coi-serviceworker.js` at the root |

```sh
make zig                          # the pinned Zig 0.17.0
site/build.sh _site               # runs make web-wasm-all if web/wasm/build/ is empty
zig run site/tools/serve.zig -- _site 8136      # http://127.0.0.1:8136/argus/
node site/tools/check.mjs --url http://127.0.0.1:8136/argus/ --out /tmp/site-check
```

## Choices

- **Facts come from the repository.** The leaderboard and the prompt are rendered from
  `BENCHMARK.md` at build time; a reworded section fails the build rather than shipping a stale
  table. Measured numbers on the pages are the engines' READMEs' (Chrome 157, Apple M3).
- **Cross-origin isolation only where threads matter.** The bench page loads
  `coi-serviceworker.js` first (one reload on the first visit, then every page under the site is
  isolated). The home page does not, so a first visit never reloads before its first frame; its
  wasm theme runs on one thread there until the visitor asks for threads (or has visited the
  bench). Without a service worker, wasm falls back to `NAME.st.wasm` on one thread.
- **No cross-origin requests.** Isolation (COEP `require-corp`) would block third-party
  embeds, so the video is a link with a local poster, and fonts are the system's.
- **Zig is not compiled in the page.** A Zig 0.17 compiler built for wasm32-wasi has no LLVM, so
  it cannot emit the ReleaseFast code the harness times, and its 32-bit `usize` would change
  Gate 1's verdicts (`expected type 'u32', found 'usize'` compiles on wasm32). A pasted `.zig`
  goes to a pull request (`.github/workflows/bench.yml` runs the native harness;
  `bench-comment.yml` posts the report), or to the local commands; an uploaded `.wasm` from
  `make web-wasm` runs through all 8 gates here. `make web-wasm` type-checks the theme for
  aarch64-macos before building it, so its Gate 1 matches the native harness.
- **The WGSL checks are the Metal harness's.** Compilation, the 320x200 watchdog, NaN/Inf,
  pixel variance, temporal motion and the 8,333 us GPU budget; alpha is shown but not gated, as
  in the Metal harness (the app presents opaque layers).
