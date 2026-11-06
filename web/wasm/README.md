# web/wasm: Argus Zig themes in the browser

Argus's Zig themes and CPU kernel ports (`themes/cpu`) compiled to WebAssembly with SIMD128,
running on every core through a Worker pool, with the harness's 8 gates in the page. It is the
same source the native harness builds: the theme file is compiled unchanged, and the gates are
`src/harness_gates.zig`, the code `make harness` runs.

```sh
make web-wasm THEME=themes/cpu/Tutorial_Tides.zig   # -> web/wasm/build/Tutorial_Tides.{mt,st}.wasm
make web-wasm-all     # the dev page's themes, the BENCHMARK.md skeleton and the gate fixtures
make web-wasm-refs    # also the native harness's report and PNG for each (for the comparison)
make web-wasm-serve   # http://127.0.0.1:8135/web/wasm/ with COOP/COEP
```

## The engine interface

Shared with the WebGPU engines (`web/host`, `web/cygnus`):

```js
import { create } from './web/wasm/host.js';
const eng = await create(canvas, { theme: 'Tutorial_Tides' });
eng.resize(w, h);                 // device pixels; the theme renders at this size
eng.frame(timeSec, dtSec);        // call once per requestAnimationFrame; never blocks
eng.stats();                      // { cpuMs, blitMs, wasmKB, fps, threads, lanes, variant, ... }
eng.destroy();
```

`create(canvas, opts)`:

| option | default | meaning |
| :--- | :--- | :--- |
| `theme` | `'Tutorial_Tides'` | build name (`build/NAME.mt.wasm`, `NAME.st.wasm`) |
| `base` | `./build/` next to host.js | URL of the build folder |
| `threads` | `'auto'` | Workers in all; `'auto'` = `navigator.hardwareConcurrency`, `1` = the single-threaded module |
| `blit` | `'auto'` | `'webgl2'` (texture upload straight from shared memory) or `'2d'` (ImageData) |
| `renderScale` | `1` | render at this fraction of the canvas each way, upscaled with linear filtering |
| `scale` | `devicePixelRatio` | the `scale` argument the theme's `init` gets |

`frame(timeSec, dtSec)` returns a promise for that frame, or `null` when the Worker was still busy.
A busy frame is not lost: its time goes into the next step, which starts as soon as the current
frame is on the canvas. A theme that costs 18 ms therefore runs at about 55 FPS on a 60 Hz
display, not 30. Time follows the app (`src/desktop/frame_rate.zig`): one SDK step of 0.008 per
1/30 s, so a frame of `dt` seconds steps `dt * 0.24`. Steps are capped at 0.25 s of wall time
after a pause.

`stats()` gives `cpuMs`, the theme's step + draw in the Worker(s) averaged over the last 60
frames, and `blitMs`, the upload and draw on the page's thread. There is no `gpuMs`: nothing
here runs on the GPU but the blit. Also `fps` (frames shown in the last second), `threads`,
`lanes` (SIMD lanes per kernel call; 0 for an SDK theme), `variant` (`'mt'` or `'st'`),
`wasmKB`, `renderW`/`renderH`, `dropped`, `nan` and `error`.

`bench(frames, dtSec)` (not part of the shared interface) runs frames back to back without rAF
and resolves to `{ msPerFrame, fps, cpuMs, blitMs, ... }`.

## How it works

- **Build.** `web/wasm/runtime.zig` is the root module and the theme is `-Mtheme=THEME`, as in
  `make linux`. The build runs twice: `NAME.mt.wasm` (`+simd128 +atomics +bulk_memory`, shared
  imported memory, 1 GiB max) and `NAME.st.wasm` (`+simd128`, single-threaded).
  `wasm32-freestanding`, `ReleaseFast`, as the harness builds natively. No relaxed SIMD: its
  results may differ between machines, and a grader must not.
- **Allocator.** Zig 0.17's std has no page allocator for threaded wasm. The runtime supplies one
  as `root.os.heap.page_allocator` (`wasm_heap.zig`), so `std.heap.page_allocator` in a theme,
  and the SDK's `CountingAllocator` around it, work unchanged.
- **SPMD lanes on v128.** `argus_kernel.zig` picks `N` from `std.simd.suggestVectorLength(f32)`,
  which is 4 with SIMD128: `F` = `@Vector(4, f32)` = one `v128`. LLVM has no f32x4 instruction for
  `@round` or IEEE `@max`, so it made each a libm call per lane. On wasm only, the kernel spells
  them as exact SIMD selects (tested bit for bit against the builtins), which cut Tides from 184
  to 78 ms per frame on one thread (Node 22). Native code is unchanged.
- **Threads.** wasm has no `std.Thread.spawn`. On wasm the kernel hands each frame to `WasmPool`:
  the drawing thread publishes the frame's `Job`, bumps an epoch word and runs `Job.run`, the
  same row-grabbing loop native threads run. Helper Workers wait on the epoch (`Atomics.wait`),
  call `argus_kernel_help` (which also runs `Job.run`) and leave. The drawing thread waits
  until every helper that joined has left, so `draw` returns a whole frame, as `join` does
  natively. Each helper is another instance of the module on the same `WebAssembly.Memory`, with
  a 1 MiB stack and a TLS block of its own (`web_thread_init`). SDK themes (`themes/*.zig`)
  draw on one thread, as they do natively.
- **Workers.** `engine.js` starts a leader Worker (it owns the theme) and, for a kernel theme,
  `hardwareConcurrency - 1` helpers. The page's thread only uploads finished frames.
- **Isolation.** Shared memory needs a cross-origin isolated page (COOP `same-origin` + COEP
  `require-corp`). GitHub Pages cannot send those headers, so `coi-serviceworker.js` (the
  [coi-serviceworker](https://github.com/gzuidhof/coi-serviceworker) approach) adds them from a
  service worker and reloads the page once. Load it first in `<head>` as a classic script. Its
  scope is its folder, so place it at the site root to cover the whole site. Without isolation (no
  service worker, a hard reload, an embed), `engine.js` loads `NAME.st.wasm` on one Worker and
  frames come back as copies.
- **Blit.** The theme writes `0xFF_BB_GG_RR` words, which are the `[R, G, B, A]` bytes that both
  ImageData and an RGBA8 texture take. WebGL2 `texSubImage2D` reads straight from the shared
  memory (0.30 ms at 1920×1200 in Chrome 157). ImageData needs a copy out of shared memory first
  (0.59 ms), so WebGL2 is the default.

## Gates in the page

`gates.js` `runGates(name)` runs the harness on a wasm build: 320×200 watchdog, then 120 frames
at 1920×1200 with `scale = 2`, `dt = 0.008`, padded stride `width + 16`, the same buffers,
canaries and checks (`src/harness_gates.zig`, compiled into the theme's own module). So the
verdict is the native harness's verdict.

| Gate | where it is decided |
| :--- | :--- |
| 1 Compilation | `make web-wasm-all` records whether `zig build-exe` succeeded (`build/NAME.compile.txt`, `manifest.json`); the page also needs the module to compile and link in this browser |
| 2-8 | `web_gates_run` in the module: `harness_gates.run`, the code `make harness` runs |
| time limit | a host-only addition: the watchdog probe gets Argus.app's 10 s (`verify_timeout_ms`), init 120 s, the frames 30 s + 2 s per frame; a theme that runs past it fails instead of hanging the page |

Fixtures in `tests/fixtures`: `Gate0_Control` passes, and `Gate1_Compile` to `Gate8_Budget` each
break one gate. `Gate4_Stride` also trips the watchdog, whose frame is padded too.
`Fixture_Hang` never returns from `step`.

Measured on 2026-11-06 on an M3 (4P+4E cores) shared with other work: one run of every build in
headless Chrome 157 (load average 85-150), and the Tides times from three later runs at load ~18.
Native is `make harness` (aarch64-macos, ReleaseFast) on the same machine the same hour:

| Build | Browser | Native | Final frame, browser vs native PNG |
| :--- | :--- | :--- | :--- |
| Tutorial_Tides (kernel, 8 Workers) | FAIL, gate 8 only: 17.2-17.5 ms | PASS, 15.3 ms | 2,304,000 / 2,304,000 equal |
| Bench_Skeleton (BENCHMARK.md §3) | PASS, 4.7 ms | PASS, 1.5 ms | all equal |
| Cygnus_A (SDK, f64) | PASS, 13.8 ms | PASS, 6.9 ms | 2,008,681 equal, max difference 17 (see below) |
| Gate0_Control | PASS | PASS | all equal |
| Gate1_Compile | FAIL 1 | FAIL (does not compile) | - |
| Gate2_Alloc | FAIL 2 | FAIL | all equal |
| Gate3_Watchdog | FAIL 3 | FAIL | all equal |
| Gate4_Stride | FAIL 3, 4 | FAIL | all equal |
| Gate5_Alpha | FAIL 5 | FAIL | not comparable: a PNG cannot hold the RGB of alpha-0 pixels |
| Gate6_Frozen | FAIL 6 | FAIL | all equal |
| Gate7_NaN | FAIL 7 | FAIL | all equal |
| Gate8_Budget | FAIL 8: 43.2 ms | FAIL, 42.4 ms | all equal |
| Fixture_Stateful | FAIL 2 | FAIL | all equal |
| Fixture_Stateless | PASS | PASS | all equal |
| Fixture_Hang | FAIL 3 (stopped after 10 s) | hangs (the harness has no time limit) | - |

Tides sits close to the 16.7 ms line in both: in Node 22 it ran at 13.6-15.1 ms (PASS), and in
Chrome at a load average of ~150 it took 16.9 ms. Gate 8 measures the machine at that moment, so
judge a theme near the line on a quiet machine.

**Why Cygnus_A is not bit-exact.** Its f64 `@exp`, `@log`, `@sin` and `@cos` are libm calls.
Natively (`-lc` on macOS) they are libSystem's; in wasm they are Zig's compiler_rt. Over 200,000
random inputs the two differ in the last bits for 9.7% of `exp`, 4.5% of `sin` and 4.3% of `cos`
results, and Cygnus's long geodesic integrations carry that into the image. Every check
still passes. Kernel themes use the kernel's own polynomials and match bit for bit.

## Speed

Chrome 157, headless (foreground), M3, 1920×1200, WebGL2 blit, load average 8-13:

| Theme | Workers | ms/frame (step + draw + blit) | max FPS | rAF FPS (60 Hz) |
| :--- | ---: | ---: | ---: | ---: |
| Tutorial_Tides | 8 | 18.0 | 55.7 | 57 |
| Tutorial_Tides | 4 | 23.4 | 42.8 | 42 |
| Tutorial_Tides | 2 | 43.7 | 22.9 | 23 |
| Tutorial_Tides | 1 (`st`) | 86.2 | 11.6 | 12 |
| Cygnus_A | 1 (SDK theme) | 16.6 | 60.3 | 55 |
| Bench_Skeleton | 1 | 3.1 | 326 | 60 |

Native `make harness` on Tides at the same time: 15.3 ms on 8 threads. Module sizes: Tides 19.1 KB
(`mt`) and 17.5 KB (`st`), Bench_Skeleton 26.6 KB, Cygnus_A 78.4 KB.

## Files

| file | what |
| :--- | :--- |
| `runtime.zig` | root module: theme ABI by name, frame buffers, live step/draw, gate run, thread bootstrap |
| `wasm_heap.zig` | `std.heap.page_allocator` for threaded wasm |
| `engine.js` | load `NAME.{mt,st}.wasm`, start leader + helper Workers on one memory |
| `worker.js` | a Worker: leader (theme, gates) or helper (kernel rows); runs in browsers and Node |
| `host.js` | `create(canvas, opts)`: the engine interface above |
| `gates.js` | `runGates(name)`: the 8 gates, with time limits, in the harness's report layout |
| `png.js` | exact PNG decode (no colour management) and pixel comparison |
| `coi-serviceworker.js` | COOP/COEP from a service worker, for hosts without headers |
| `serve.mjs` | local static server with (or `--no-isolation`, without) the headers |
| `index.html` | dev page: live view and HUD, gates for one build or all, native comparison |

The page reads `?theme=`, `?threads=`, `?scale=`, `?blit=` and `?gates=1|all`.

## Not here yet

- **Compiling in the browser** is in `web/zigc` (the bench page): zig.wasm builds a pasted theme
  with Zig's self-hosted wasm backend, single-threaded and without SIMD, and grades it here
  through `opts.module`. The SIMD128 and threaded builds above still need `make web-wasm`.
- **Threads for SDK themes.** A theme that draws its own rows (Cygnus_A, the skeleton) runs on
  one thread, as it does natively. Spreading them would mean a row-range draw in the SDK.
- **Safari and Firefox** were not tested: this was measured in Chrome 157 and Node 22.
