# web/zigc: Zig 0.17.0 in the browser, for the bench page

Drop or paste a `.zig` theme on the bench page (`site/bench/`). It is compiled in the page by the
Zig 0.17.0 compiler built to WebAssembly (`zig.wasm`), run, and graded by the harness's gates
(`web/wasm/gates.js`, which runs `src/harness_gates.zig` inside the theme's module). There is no
server and no pull request. The pull request route (`bench/submissions/`, the bench workflow)
stays the official verdict.

```sh
make web-zigc ZIG_WASM=path/to/zig.wasm    # -> web/zigc/build/ (gitignored), shipped by site/build.sh
make web-zigc-test ZIG_WASM=path/to/zig.wasm   # Node: the page's compile on the fixtures
site/build.sh _site && node web/zigc/verify.mjs --browser Safari   # the page itself, in a browser
```

`zig.wasm` is built in CI (`.github/workflows/pages.yml`, `tools/get-zig-wasm.sh`) from the
official source tarball, checked against the SHA-256 that ziglang.org/download/index.json lists:
`zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseSmall -Denable-llvm=false -Ddev=wasm
-Dversion-string=0.17.0 -Dno-lib`. It is 4.2 MB and is never committed.

## What a compile does

Two runs of the compiler, as `make web-wasm` does natively (`zigc.js`):

1. **Gate 1**: `zig build-obj -fno-emit-bin -target wasm64-freestanding THEME`, type-checked only.
   Natively `make web-wasm` checks for `aarch64-macos`. This `zig.wasm` (`-Ddev=wasm`) cannot:
   Sema asks the target's backend about every `callconv(.c)` function, and the build has
   neither the aarch64 nor the LLVM backend, so it stops with "development environment wasm does
   not support feature aarch64_backend". wasm64 also has a 64-bit `usize`, so
   `const x: u32 = n_usize;` fails here with the native error at the same file:line:col:
   `expected type 'u32', found 'usize'` ("unsigned 32-bit int cannot represent all possible
   unsigned 64-bit values"). What it does not cover is the OS: code that needs macOS or libc is
   checked against freestanding.
2. **The module**: `zig build-exe -fno-llvm -fno-lld -target wasm32-freestanding -mcpu=generic
   -fsingle-threaded`, with `web/wasm/runtime.zig` and `src/harness_gates.zig` as in
   `make web-wasm`, through `root.zig` (below). The page then runs it on the existing engine
   (`opts.module`).

Errors are Zig's own, with `file:line:col`; on the page each links to that place in the editor.
If Gate 1 passes but the self-hosted backend cannot build the theme (a backend limit, not a
verdict), the page says so and sends you to the native harness.

## Where it differs from `make web-wasm`, and why

Zig 0.17.0's self-hosted wasm backend (the only backend in this `zig.wasm`) has gaps. Each one
was hit here and worked around or recorded:

| gap | what happens | here |
| :--- | :--- | :--- |
| An exe's compiler_rt is built as a library, written as a bare object named `.a` | `failed to parse archive: BadArchiveMagic` | `root.zig` compiles `lib/compiler_rt.zig` into the same compilation (`-Mcompiler_rt=/lib/compiler_rt.zig`), as Zig does for an object |
| Its linker cannot read its own objects (no `target_features` section) | `failed to parse object: MissingFeatures` | (same fix) |
| An undefined weak function is a link error | `undefined function: argus_render_theme` | `zigc.js` links, reads which optional ABI functions are undefined, and links again with them listed (`root.web_absent`); `runtime.zig`'s `weak()` then gives null, as dlsym does |
| `@setFloatMode(.optimized)` | `TODO implement optimized float mode` | `argus_kernel.zig` uses `.strict` under this backend only (`fast_math`) |
| `+simd128` output | does not validate: "type error in branch, expected v128, got i32" on a function returning a `@Vector`; Tides traps at run time | `-mcpu=generic`: vectors are lowered to scalar code |
| threads (`+atomics`, shared memory) | does not validate: "invalid atomic opcode" in compiler_rt's `__atomic_fetch_sub_2`; its inline assembler has no `global.get`/`global.set` for a Worker's stack | single-threaded only |

LLVM builds are unchanged by these edits: `make web-wasm` gives byte-identical
`Tutorial_Tides` and `Gate0_Control` modules (mt and st) before and after.

Against LLVM's `+simd128` wasm, the kernel's functions (`sin`, `cos`, `exp2`, `noise`, `fbm`,
`hash`, `pack`, ...) give bit-identical results over 4,096 inputs each, except `log2` (168
values) and `srgb` (40) one ulp off: the strict float mode above.

**Speed.** Scalar code is close to LLVM's: the BENCHMARK.md skeleton runs at 3.5 ms/frame in
Node either way, Cygnus_A at 64 ms (LLVM wasm: 13.8 ms), Gate8_Budget at 70 ms (native: 42 ms).
`@Vector` code is far slower: the kernel's functions run 100-400x slower than LLVM's in Node,
and Tutorial_Tides draws 320x200 in 357 ms in Node, 147 ms in Chrome and 103 ms in Safari 26.6
(1920x1200: 13 s in Node; LLVM's single-threaded wasm: 86 ms in Chrome). So Gate 8 on the page is labelled as this build's time,
and the official Gate 8 is the native harness's. Before grading, the page times one 320x200
frame; if the gates' 120 frames at 1920x1200 would take over 90 s, it shows Gate 1, runs the
theme live at a size it can draw, and offers to run the gates anyway.

## Every run ends, visibly

A run (a compile here, a prebuilt build, an upload) always ends with a verdict or a message. A
new run cancels the one in flight, the Cancel button cancels it, and the progress line shows
what it is doing and for how long.

| stage | limit | then |
| :--- | :--- | :--- |
| loading the compiler | each download 3 tries (20 s without data fails a try); 45 s without progress | "the compiler did not load: ..."; the next compile loads afresh |
| compiling | 60 s (`client.js`) | the Worker is terminated: "the compiler did not finish in 60 s", with Zig's output so far |
| zig.wasm traps | - | the message by kind (`wasi.js` WasiCrash): out of stack, out of memory (also Zig's own `error: OutOfMemory`), a Zig panic with its text, any other trap. Gate 1 is "not decided" here |
| a Worker error, an unreadable message | - | the Worker is terminated; the next compile gets a fresh one |
| loading the module in the page | 30 s | "Zig built a module that this browser could not load" |
| speed probe | 10 s, Workers terminated | the gates run (their watchdog decides) |
| starting the gate Workers | 15 s | Gate 3 FAIL: "the module did not start in a Worker" |
| the gates | watchdog 10 s, init 120 s, frames 30 s + 2 s each (as before) | Gate 3 or 8 FAIL "hung"; a trap (a panic, out of memory) is Gate 3 or 8 FAIL "crashed: ..." |
| the live view | 15 s to start | "Live view failed" |

After a crash, a time-out or a cancel the compiler's Worker is thrown away (zig.wasm's memory
with it), and so is a Worker whose zig.wasm grew past 1.5 GB. `/cache` is saved to IndexedDB
only after runs where zig.wasm exited normally, with its SHA-256; a record that does not verify
or unpack is deleted on load (the page says so) and the compile starts from an empty cache. A
crash with a restored cache is retried once without it.

Editing the source marks the result below as out of date. A paste that fills the editor (it was
empty, or all of it was selected) compiles at once, as a paste outside a field does.

**Pathological inputs** (`cases.js`, in `make web-zigc-test` and `verify.html`): endless
comptime recursion, a 256 MB comptime table, 200,000 nested parentheses, endless loops in init
and in step, an allocation storm, 500 KB of source, 64 KB of random bytes. Each ends with its
expected outcome within its limit, and the skeleton compiles and passes after each. Two of
them differ from native Zig, and the page says why:

- Endless comptime recursion: native Zig stops it with "evaluation exceeded 1000 backwards
  branches" (Gate 1 FAIL). zig.wasm runs on the browser's stack, which is far smaller, and
  overflows first: comptime recursion reaches 100-200 calls in Node's default stack (400 with
  a 4 MB stack). The page reports "the compiler ran out of stack", Gate 1 not decided.
- A 256 MB comptime table: zig.wasm grows to 3.1 GB and reports OutOfMemory after 12-13 s (Node,
  Chrome). The page reports "the compiler ran out of memory", Gate 1 not decided.

200,000 nested parentheses crash native Zig too (stack overflow).

## The standard library bundle

Zig runs AstGen on every file reachable through an `@import("x.zig")` string, analysed or not,
so every compile reads the whole import closure of `std/std.zig` and `compiler_rt.zig`: 698
files. `bundle.zig` follows those imports and bundles exactly that closure from the release's
`lib/` (the rest of `lib/`, 242 MB of libc headers and sources, is never opened). The release
ships the closure's 86 test files empty, so it is 18.0 MB (3.26 MB gzipped); the source
tarball's is 31.5 MB. The closure the tool finds is the set of files the compiler actually
opened (logged through the WASI layer), with none missing and none extra, and the 12 test
modules are byte-identical when built from either lib.

## Measured (M3, 2026-11-06, served locally under /argus/ without COOP/COEP, as Pages)

Downloads on first use: 4,593,211 bytes (zig.wasm.gz 1,331,530 + zig-lib.bin.gz 3,261,681); 0 on
the next visit. Compile of the BENCHMARK.md skeleton (Gate 1 type-check + module build):

| | first visit | next visit (Cache API + IndexedDB) |
| :--- | :--- | :--- |
| Chrome (built-in pane) | 0.76 s + 0.42 s | 0.08 s + 0.25 s (pane hidden: throttled) |
| Safari 26.6 | 0.98 s + 0.48 s | 0.12 s + 0.40 s |
| Node 22 (`test.mjs`) | 1.5 s + 0.55 s | 0.06 s + 0.26 s (same process) |

Later compiles in the same tab: 20-150 ms type-check, 180-400 ms build. Every gate fixture,
the skeleton, the u32/usize trap and Tutorial_Tides gave their expected verdicts in Node, the
built-in pane (Chrome engine) and Safari 26.6 (`verify.mjs`).

## Caching

The Worker checks both downloads against `build/manifest.json`'s SHA-256 and keeps them in the
Cache API under that hash. Zig's `/cache` (the ZIR of the lib, about 43 MB) is kept in
IndexedDB, keyed by the two hashes. On a second visit nothing is downloaded and AstGen is
skipped: Gate 1's type-check goes from 1.2 s to under 0.1 s in Node.

## Files

| file | what |
| :--- | :--- |
| `wasi.js` | WASI preview1 with an in-memory filesystem and full rights; preopens `.`, `/lib`, `/cache` (Node's `node:wasi` denies zig.wasm's opens on a rights mismatch) |
| `zigc.js` | the two compiler runs, the absent-symbol relink, diagnostics parsing |
| `root.zig` | the root module for in-page builds: `runtime.zig` + compiler_rt + `web_absent` |
| `stdlib.js` | mounts the bundle (views, no copies); packs and unpacks `/cache` |
| `worker.js`, `client.js` | the compiler in a Worker; the page's handle on it, loaded on first use |
| `bundle.zig` | the std import closure as one file |
| `build.sh` | `web/zigc/build/`: `zig.wasm.gz`, `zig-lib.bin.gz`, support sources, `manifest.json` |
| `node.mjs` | run zig.wasm in Node through `wasi.js` with any arguments |
| `test.mjs` | the page's compile and gates on the fixtures and `cases.js`, in Node (`make web-zigc-test`) |
| `cases.js` | the pathological inputs |
| `verify.html`, `verify.mjs` | drive the real bench page in a browser and collect the verdicts |
