# ARGUS-BENCH // Bare-Metal Zig 0.17.0 Visual & Physics Benchmark

**`ARGUS-BENCH`** is a standalone, deterministic systems-and-physics benchmark for AI coding agents built on top of **Argus** (`Argus.app`), the bare-metal Zig 0.17.0 macOS multi-Space Retina wallpaper engine.

Instead of grading models on boilerplate CRUD apps or subjective web shaders, `ARGUS-BENCH` challenges an AI system to produce **a single, self-contained, zero-dependency Zig 0.17.0 source file** (`themes/<Agent_Theme>.zig`) that simulates a real mathematical or physical system and rasterizes a **`1920×1200` Retina framebuffer on the CPU at 60–1,200+ FPS** under strict memory, stride-canary, and numerical-stability invariants.

Every submission that passes the automated harness (`src/theme_harness.zig`) is also a live wallpaper: drop the file on a Desktop Space from Argus's menu bar and the app compiles it to an `aarch64-macos` `.dylib`, checks it in an isolated watchdog process, and runs it.

---

## How to run it

There are two modes. Say which one you ran when you report a result: they are not comparable.

### Zero-shot (a model in a chat window, no tools)

1. Give the model this whole file and the prompt below.
2. Save its answer as `themes/<Model>_<Name>.zig` in a clone of the repository.
3. Run `make harness THEME=themes/<Model>_<Name>.zig`. The result is the first verdict: no retries,
   no edits by hand.

> *"Read `BENCHMARK.md` carefully. Write a single, complete, plug-and-play Zig 0.17.0 theme file for Argus following all 8 Hard Harness Gates (`Allocs at Init == 1`, `Allocs after Init == 0`, `Watchdog 320x200: PASS`, `y * stride + x` indexing, `0xFF` alpha on every pixel, zero NaNs, `Temporal Motion >= 2000 animated pixels`, `< 16.6 ms/frame` at `1920x1200` on CPU). Prefer `sdk.addRGB`, `sdk.scaleRGB`, `sdk.lerpRGB`, and `sdk.Canvas` to avoid Zig 0.17 peer-type narrowing and unsigned subtraction underflow. Output ONLY the complete `.zig` source file ready to save as `themes/<YourModel>_<ThemeName>.zig`."*

### Agentic (a coding agent with a shell, in a clone)

For Claude Code, Codex, Gemini CLI and the like. The agent runs the harness itself and iterates.
The prompt is one line:

> *"Run ARGUS-BENCH in agentic mode: follow the agentic steps in `BENCHMARK.md` and pick a track from §5."*

1. **Set up.** `git clone https://github.com/gke0op/argus.git && cd argus && make zig` (installs
   the pinned Zig 0.17.0 into `.toolchain/`, checksum-verified).
2. **Prove the toolchain.** Copy the skeleton in §3 to `themes/<Model>_<Name>.zig` unchanged and run
   `make harness THEME=themes/<Model>_<Name>.zig`. It must print `Verdict : PASS` before you change
   anything. If it does not, the problem is the setup, not your theme.
3. **Pick a track** (§5) and a real system to simulate.
4. **Build it in small steps.** Run the harness after each change. A failing gate names itself on
   its line of the report; §1 says what usually causes each one, §4 lists the Zig 0.17.0 traps.
5. **Look at it.** `make harness THEME=... OUT=/tmp/<Name>.png` writes the last frame. Open it.
   Passing the gates proves the theme runs, not that it looks like anything.
6. **Report** the final scorecard (verdict, average frame time and tier from §2), how many harness
   runs it took to the first PASS, and the PNG.

To go beyond the gates, to a theme good enough to ship, the bar and the render-and-critique loop
are in [`.claude/skills/THEME_CRAFT.md`](.claude/skills/THEME_CRAFT.md).

---

## 1. The 8 Hard Harness Gates (Automated Pass/Fail Oracle)

When your `.zig` file is placed in `themes/` and evaluated via:

```sh
make harness THEME=themes/Your_Theme.zig
```

the Argus Headless Harness (`src/theme_harness.zig`) compiles your file into a dynamic library (`zig build-lib -dynamic -O ReleaseFast -target aarch64-macos -lc`), runs the `Argus.app` `320×200` safety watchdog probe, and renders **120 frames** at **`1920×1200`** (`scale = 2.0`, fixed timestep `dt = 0.008`).

Your submission **PASSES** if and only if all **8 hard gates** succeed simultaneously:

| Gate | Harness Invariant | Exact Requirement | Common Failure Mode to Avoid |
| :--- | :--- | :--- | :--- |
| **Gate 1: Compilation** | `zig build-lib -O ReleaseFast` | Exits `0` with zero errors under **Zig 0.17.0** | Using deprecated Zig 0.11–0.14 builtins (`@intToFloat`, `@floatToInt`, `@hypot`, or uncasted `@truncate(x) % N`) |
| **Gate 2: Single-Alloc Arena** | `Allocs at Init == 1` & `Allocs after Init == 0` | Exactly **1** heap allocation during `init()` (`alloc.create(State)`, recommended `<= 16 MiB`) and **0** allocations during 120 `step()`/`draw()` frames | Calling `alloc.alloc(...)` inside `init()` in addition to `alloc.create(State)` (makes `Allocs at Init == 2` → **FAIL**). Put all LUTs/arrays directly inside `State`! |
| **Gate 3: Watchdog `320×200` Probe** | `Watchdog 320x200: PASS` | Before loading a `.dylib` into `Argus.app`, the watchdog runs `init(320, 200, 1.0)` + `step(0.008)` + `draw(buf_320x200, 320)` | Hardcoding a sub-window size like `CORE_SIZE = 384` and computing unsigned `(self.h - CORE_SIZE) / 2` (`200 - 384` underflows `usize` and segfaults!). Always use signed `isize` coordinates or `sdk.Canvas`! |
| **Gate 4: Stride Canary** | `Stride Guard: CLEAN` | `draw(buf, stride)` runs for 119 frames on a padded buffer (`stride = width + 16`) with `0xDEADBEEF` canaries in columns `[width .. width + 16]` | Indexing `buf[y * self.w + x]` instead of `buf[y * stride + x]`, or calling `@memset(buf, ...)` across the full slice instead of row-by-row `buf[y * stride .. y * stride + self.w]` |
| **Gate 5: Pixel & Alpha Integrity** | `alpha=0 count: 0` & `distinct_pixels > 100` | Every pixel `(x, y)` in `0..width × 0..height` must be written with opaque alpha `0xFF` (`sdk.packRGBA(r, g, b)`), with non-trivial visual variance | Leaving unrendered corners at `0x00000000` (`alpha=0`), or packing `0x00RRGGBB` without the `0xFF000000` alpha byte |
| **Gate 6: Temporal Motion** | `Temporal Motion >= 2000` | Frame 120 must differ from Frame 1 (`|dR| + |dG| + |dB| >= 4`) on at least `2,000` pixels | Updating particle/wave state in `step(dt)` without wiring that dynamic state into `draw()`, or over-attenuating dynamic disk brightness to `(0, 0, 0)` so only the static starfield is visible |
| **Gate 7: Numerical Stability** | `NaN / Inf Check: CLEAN` | `hasNaN()` returns `false` on every frame; no division-by-zero or domain errors in `@sqrt` / `@log` / `std.math.acos` | Calling `@sqrt(x)` without `@max(0.0, x)` or `std.math.acos(x)` without `std.math.clamp(x, -1.0, 1.0)` |
| **Gate 8: Frame Budget** | `Avg Frame Time < 16667.0 us` | Must sustain at least **60 FPS** (`< 16,667 µs/frame`) at `1920×1200` (`2,304,000` pixels/frame) on a single CPU thread | Evaluating expensive transcendental functions (`@sin`, `@cos`, `@exp`, `@atan2`) per-pixel across all 2.3M pixels inside `draw()` instead of precomputing LUTs in `init()` or 1D/coarse tables in `step()` |

---

## 2. Performance Tiers & Current Reference Leaderboard

Submissions that pass all 8 gates are ranked by average frame time across 120 frames at `1920×1200` Retina resolution (`2,304,000` pixels/frame, single-thread CPU `ReleaseFast` on Apple Silicon):

- **Platinum Tier (`1,000+ FPS`):** `< 1,000 µs / frame`
- **Gold Tier (`500+ FPS`):** `< 2,000 µs / frame`
- **Silver Tier (`240+ FPS`):** `< 4,167 µs / frame`
- **Bronze Tier (`60+ FPS`):** `< 16,667 µs / frame`

### Reference Baselines

Of these baselines only `themes/Cygnus_A.zig` ships in this release. The others did not ship;
they stay in the git history (`git log --all -- themes/<name>`) as reference submissions.

| Theme File | Author / Agent | Physics / Mathematical Simulation | Init Memory (`1 alloc`) | Avg Frame Time (`1920×1200`) | Effective FPS | Tier |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`themes/Cygnus_A.zig`** | Claude Opus | The quasar engine (generated from `tools/quasar_template.zig`) modelled on Cygnus A, the hidden quasar in the archetypal radio galaxy: $2.5\times10^9\,M_\odot$, $0.012\,L_{\rm Edd}$, an honestly thin disk; spin unmeasured, $a/M=0.9$ chosen (CPU path shown; the app draws it on the GPU by default) | `61,368,016 B` (`58.52 MiB`) | **`5,278–5,316 µs`** | **`188–189 FPS`** | Bronze |

### The seven shipped themes: measured cost

Apple GPUs stay at low clocks when Argus paces frames at 30 FPS, so a theme's live cost is higher than its back-to-back cost. Judge GPU themes on the **paced** column (`make harness THEME=themes/X.metal` prints it as "Paced 30 FPS"). Measured on an M3 with 8 GB, 3 runs per theme; GPU busy, CPU and memory come from `Argus --offscreen --bench-space 0 --perf-log` with the theme on one Space (and on four, for the last column). An empty Argus costs 13 MB, 0.2% CPU and no GPU.

| Theme | Back-to-back GPU | Paced 30 FPS GPU | GPU busy in Argus, 30 FPS | Argus CPU | Memory, 1 Space | Memory, 4 Spaces |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `themes/Tutorial_Tides.metal` | 0.63 ms | 1.27–1.36 ms | 7.4% (7.1–9.4) | 1.8–2.9% | 83 MB | 111 MB |
| `themes/Ebru_Studio.metal` | 1.02 ms | 1.69–1.72 ms | 11.2% (9.2–11.9) | 2.1–2.4% | 114 MB | 215 MB |
| `themes/Tutorial_Reef.metal` | 1.11–1.17 ms | 1.69–2.06 ms | 15.2% (10.2–15.4) | 1.6–2.2% | 91–100 MB | 139 MB |
| `themes/Orion_Nebula.metal` | 1.69–1.71 ms | 2.02–2.75 ms | 14.3% (14.3–18.4) | 1.5–2.2% | 93 MB | 152 MB |
| `themes/Night_Tide.metal` | 2.52 ms | 2.73–2.90 ms | 25.3% (17.9–36.8) | 1.6–1.9% | 89–98 MB | 143 MB |
| `themes/Lizard_Island.metal` | 2.98–3.05 ms | 3.9–4.2 ms | ~32% (21–55)\* | 1.7–2.8% | 186–195 MB | 414–506 MB |
| `themes/Cygnus_A.zig` on the GPU (HDR10, native 3024×1964) | 1.57–1.60 ms | 2.58–2.78 ms | 12.0% (11.9–12.3) | 1.0–3.1% | 276–299 MB | 387 MB |

- \*Lizard_Island was measured later with the live app running alongside (itself showing Lizard Island), which inflates its GPU busy figure. Its memory is higher because each Space keeps its own 2048×2082 float16 state texture pair (~68 MB).
- Metal themes render at 1920×1200; Cygnus_A traces and shades at the display's native size.
- Cygnus_A also runs a one-time GPU ray trace per load (3.9 s at 3024×1964), shared by every Space
  showing it; its CPU column is the theme's step() plus frame setup on the main thread.
- "GPU busy in Argus" is median (range) over 3 runs: the share of GPU time Argus's process used
  while drawing one Space at 30 FPS. It includes acquiring and presenting the drawable and the low
  GPU clock between frames, so it is higher than paced cost × 30.
- Only the Space on screen draws; extra Spaces with the theme cost memory, not GPU (the 4-Space runs'
  GPU falls inside the 1-Space range).

---

## 3. Complete SDK Contract (`themes/argus_theme_sdk.zig`)

Your file will be saved at `themes/<Your_Theme_Name>.zig` in the same directory as `argus_theme_sdk.zig`. You do **not** need any external files other than `@import("std")` and `@import("argus_theme_sdk.zig")`.

### What `argus_theme_sdk.zig` Provides

```zig
const std = @import("std");
const sdk = @import("argus_theme_sdk.zig");

/// Packs 8-bit R, G, B into Argus's native little-endian u32 pixel format:
/// Word = 0xFF_BB_GG_RR -> bytes in memory [R, G, B, 255].
/// ALWAYS use `sdk.packRGBA(r, g, b)` for every pixel written to `buf`.
pub inline fn packRGBA(r: u8, g: u8, b: u8) u32;

/// Packs 8-bit R, G, B, A with premultiplied alpha.
pub inline fn packPremulRGBA(r: u8, g: u8, b: u8, a: u8) u32;

/// Saturating additive blend of two `packRGBA` pixels (immune to Zig 0.17 `@min(255, x)` u8 narrowing).
pub inline fn addRGB(c1: u32, c2: u32) u32;

/// Scales an RGB pixel by an 8-bit fixed-point weight `scale_256` in `[0..256]`.
pub inline fn scaleRGB(c: u32, scale_256: u32) u32;

/// Linearly interpolates between `c0` and `c1` using fixed-point `t_256` in `[0..256]`.
pub inline fn lerpRGB(c0: u32, c1: u32, t_256: u32) u32;

/// Resolution-independent, stride-aware, bounds-checked canvas wrapper.
/// Prevents unsigned `usize` subtraction underflow when tested at 320x200 in `--verify-dylib`.
pub const Canvas = struct {
    buf: []u32,
    w: usize,
    h: usize,
    stride: usize,
    pub inline fn init(buf: []u32, w: usize, h: usize, stride: usize) Canvas;
    pub inline fn clear(self: Canvas, color: u32) void;
    pub inline fn setSigned(self: Canvas, x: isize, y: isize, color: u32) void;
    pub inline fn addSigned(self: Canvas, x: isize, y: isize, color: u32) void;
};

/// Generates all C-ABI symbols (`argus_theme_init`, `argus_theme_deinit`, `argus_theme_step`,
/// `argus_theme_draw`, `argus_theme_allocs_init`, `argus_theme_allocs_after_init`,
/// `argus_theme_bytes_live`, `argus_theme_has_nan`, `argus_render_theme`).
pub fn exportTheme(comptime State: type) void;
```

### Minimal Working Skeleton (Copy & Build From This)

It passes all eight gates as it stands (about 1.5 ms a frame on an M3): a night-blue gradient
with a slow swell of light moving through it. Replace the swell with your simulation.

```zig
const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    // IMPORTANT (Gate 2): Put all lookup tables, grids, and particle arrays directly
    // inside `State` as fixed-size arrays so `alloc.create(State)` is the ONLY heap
    // allocation (`Allocs at Init == 1`, `Allocs after Init == 0`).
    // Keep `@sizeOf(State) <= 12 * 1024 * 1024` (12 MiB).
    bg_lut: [MAX_PIXELS]u32,
    row_glow: [MAX_H]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.row_glow = @splat(sdk.packRGBA(0, 0, 0));

        // Precompute static geometry / LUTs once here in `init()`: a night-blue gradient.
        for (0..self.h) |y| {
            const t: u32 = @intCast((y * 256) / @max(@as(usize, 1), self.h));
            const row = sdk.lerpRGB(sdk.packRGBA(4, 6, 18), sdk.packRGBA(10, 24, 48), t);
            for (0..self.w) |x| {
                self.bg_lut[y * self.w + x] = row;
            }
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        // Advance physics / ODE / PDE / phase state using fixed timestep `dt` (0.008 s).
        // Zero heap allocations allowed here. Per-row work (h sines), not per-pixel.
        self.time_sec += dt;
        for (0..self.h) |y| {
            const fy: f64 = @floatFromInt(y);
            const s = 0.5 + 0.5 * @sin(fy * 0.02 - self.time_sec * 3.0);
            const g: u8 = @intFromFloat(s * 40.0);
            const b: u8 = @intFromFloat(s * 90.0);
            self.row_glow[y] = sdk.packRGBA(0, g, b);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        // IMPORTANT (Gate 3 & Gate 4):
        // 1. Always index row `y` via `y * stride + x` (NEVER `y * self.w + x` in `buf`).
        // 2. Write every pixel in `0..self.h` and `0..self.w` with `0xFF` alpha (`sdk.packRGBA`).
        // 3. Never write to columns `[self.w .. stride]`: those contain `0xDEADBEEF` canaries!
        const w = self.w;
        for (0..self.h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.bg_lut[y * w .. y * w + w];
            const glow = self.row_glow[y];
            for (dst_row, src_row) |*dst, src| dst.* = sdk.addRGB(src, glow);
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}
```

---

## 4. Zig 0.17.0 Survival Guide (Read to Avoid Zero-Shot Compile Errors)

If your training weights default to Zig 0.11–0.14 syntax, apply these exact **Zig 0.17.0** rules:

1. **Numeric Cast Builtins & Result Location Semantics (CRITICAL):**
   - Integer $\to$ Float: `@as(f64, @floatFromInt(int_val))` or `@as(f32, @floatFromInt(int_val))` (NEVER `@intToFloat`).
   - Float $\to$ Integer: `@as(usize, @intFromFloat(flt_val))` or `@as(i32, @intFromFloat(@floor(flt_val)))` (NEVER `@floatToInt`).
   - Integer $\to$ Integer: `@as(u8, @intCast(val))` / `@as(u32, @truncate(val))`.
   - Float $\to$ Float: `@as(f32, @floatCast(f64_val))`.
   - **TRAP 1 — Cast Builtins Inside Binary Operators (`%`, `&`, `|`, `+`, `<<`):** In Zig 0.17.0, result types do **NOT** propagate through binary operators into `@truncate`, `@intFromFloat`, `@intCast`, or `@bitCast`.
     - **WRONG (Compile Error):** `const x: u32 = @truncate(rng >> 40) % 256;` or `const idx: u32 = @intFromFloat(v) & 1023;`
     - **RIGHT:** `const x: u32 = @as(u32, @truncate(rng >> 40)) % 256;` and `const idx: u32 = @as(u32, @intFromFloat(v)) & 1023;`
   - **TRAP 2 — `@min(255, expr)` Narrows to `u8`:** In Zig 0.17.0, `@min(@as(u32, 255), x)` narrows its return type to `u8` because `255` is comptime-known to fit in `u8`! Shifting `r << 16` then fails with `error: type 'u3' cannot represent integer value '16'`.
     - **WRONG (Compile Error):** `const b = @min(@as(u32, 255), val); return b << 16;`
     - **RIGHT:** Always annotate the variable type explicitly: `const b: u32 = @min(@as(u32, 255), val); return b << 16;`
   - **TRAP 3 — Signed `i32` Hashing with Large `u32` Constants:** Constants `>= 0x80000000` (like `3812015801`) overflow `i32`. Bitcast signed ints to `u32` first: `const ux: u32 = @bitCast(ix);`.
   - **TRAP 4 — Unmutated `var` Is a Hard Compile Error:** Zig 0.17.0 rejects any `var` that is never mutated (`error: local variable is never mutated`). Use `const` unless you reassign the variable.
   - **TRAP 5 — Reserved Keyword `packed` & Primitive Integer Shadowing (`i0`, `i1`, `u0`, `u1`):** Never name a variable `packed` (reserved keyword), and never name variables `i0`, `i1`, `i2`, `i3`, `u0`, `u1` (in Zig, `i<N>` and `u<N>` are arbitrary bit-width integer types, so `const i0: usize` fails with `error: name shadows primitive 'i0'`). Use `packed_word`, `idx0`, `idx1`, etc.
   - **TRAP 6 — `@abs(signed_int)` Returns an Unsigned Integer:** In Zig 0.17.0, `@abs(x)` on an `i32` returns `u32` (not `i32`!). Writing `const absolute: i32 = @abs(signed_i32);` fails with `error: expected type 'i32', found 'u32'`. Use `const absolute: u32 = @abs(signed_i32);`.
2. **Math Builtins vs `std.math`:**
   - Builtins (call with `@`): `@sqrt(x)`, `@sin(x)`, `@cos(x)`, `@exp(x)`, `@log(x)`, `@floor(x)`, `@ceil(x)`, `@round(x)`, `@abs(x)`, `@min(a, b)`, `@max(a, b)`, `@mod(a, b)`, `@rem(a, b)`, `@mulAdd(f32, a, b, c)`.
   - `std.math` functions: `std.math.atan2(y, x)` (2 arguments, `y` first!), `std.math.hypot(x, y)` (NOT `@hypot`!), `std.math.acos(x)`, `std.math.asin(x)`, `std.math.tanh(x)`, `std.math.pow(f64, x, y)`, `std.math.clamp(val, lo, hi)`, `std.math.isNan(x)`, `std.math.isInf(x)`, `std.math.pi`.
   - **NEVER** call `@atan2` or `@hypot` (they are `std.math.atan2` and `std.math.hypot`), and **NEVER** call `std.math.fabs` (it is `@abs`).
3. **Array & SIMD Initialization:**
   - Fill an array or `@Vector(N, T)` with a scalar using `@splat(value)`:
     ```zig
     var lut: [1024]f32 = @splat(0.0);
     ```
4. **No OS / I/O Calls & No Bounding-Box Seams:**
   - Do **not** use `std.time`, `std.fs`, `std.io`, or `std.process` in a theme file. Deterministic simulation time is driven exclusively by `dt: f64` in `step(self: *State, dt: f64)`.
   - If you use an active bounding box overlaid on `bg_lut`, ensure intensity/palette `0` adds `(0, 0, 0)` (or smoothly vignettes to `0.0` at the box radius) so the rectangular bounding box border is completely invisible.
5. **Engineering for `< 1,500 µs/frame` at `1920×1200`:**
   - `1920 × 1200 = 2,304,000` pixels per frame.
   - Do **not** compute `@sin`, `@cos`, `@exp`, `std.math.atan2`, or multi-step ray marches for all `2,304,000` pixels inside `draw()`.
   - **Pattern A (Precomputed Pixel Coordinate / Geodesic LUT + Fast Per-Frame Phase):** Precompute static per-pixel polar/geodesic/ray coordinates into a compact `struct` (`<= 4–8 bytes/pixel`) or bounding-box sub-region inside `init()`, and evaluate 1D harmonic tables (`[1024]f32`) in `step()` so the inner loop in `draw()` is pure table lookups and integer/FMA arithmetic.
   - **Pattern B (Active Bounding Box + Cached Static Deep-Space Background):** Precompute the rich static starfield/nebula background into `bg_rgba: [MAX_PIXELS]u32` in `init()`, copy rows via `@memcpy(buf[y * stride .. y * stride + w], ...)` (or only overwrite the dynamic bounding box after painting the background), and concentrate per-pixel math inside the active physical region.

---

## 5. Benchmark Challenge Tracks

You may submit a theme for any of the three tracks below (or propose a novel physical simulation):

### Track A — Relativistic & Astrophysical Singularity (`themes/<Model>_Relativity.zig`)
Build a physically grounded general-relativistic or high-energy astrophysical visualization at `1920×1200` (e.g., a binary black hole merger with gravitational-wave spacetime strain + lensed accretion streams, or a relativistic wormhole throat connecting two distinct starfields via Ellis–Bronnikov null geodesics).

### Track B — Symplectic / PDE Field Dynamics (`themes/<Model>_Field.zig`)
Simulate a live time-evolving partial differential equation or Hamiltonian many-body system in `step(dt)` and render it at `1920×1200` (e.g., 2D compressible MHD / Navier–Stokes vortex turbulence with Lagrangian tracer filaments, Gross–Pitaevskii quantum Bose–Einstein condensate vortex lattices, or coupled reaction-diffusion / Schrodinger wave caustics).

### Track C — Grandmaster Freeform (`themes/<Model>_Masterpiece.zig`)
No topic restrictions: design the most visually hypnotic, mathematically deep, high-FPS `1920×1200` Retina desktop wallpaper your architecture can conceive within a single Zig 0.17.0 file.

---

## 6. How Your Submission Is Evaluated

1. Save the theme as `themes/<Model>_<Name>.zig`.
2. Run the automated harness:
   ```sh
   make harness THEME=themes/<Model>_<Name>.zig FRAMES=120 OUT=/tmp/<Model>_<Name>.png
   ```
3. The harness prints the deterministic scorecard. This one is the §3 skeleton:
   ```text
   ========================================================================
    ARGUS HEADLESS THEME HARNESS (Zig 0.17.0) // VERIFICATION REPORT
   ------------------------------------------------------------------------
    Theme             : themes/Skeleton.zig (Stateful SDK Contract)
    Resolution        : 1920x1200 (tested stride=1936, stride=1920, and 320x200 watchdog)
    Frames Rendered   : 120 (fixed dt = 0.008000)
    Avg Frame Time    : 1541.7 us (648.6 FPS) | Budget: 16667.0 us
    Worst Frame Time  : 3643.0 us
    Allocs at Init    : 1 (9220832 bytes)
    Allocs after Init : 0
    Watchdog 320x200  : PASS
    Stride Guard      : CLEAN (0 out-of-bounds canary writes)
    NaN / Inf Check   : CLEAN
    Pixel Variance    : 2300160 / 2304000 non-bg pixels (alpha=0 count: 0)
    Temporal Motion   : 2259840 / 2304000 visibly animated pixels (min required: 2000)
    Output PNG        : /tmp/Skeleton.png
    Verdict           : PASS
   ========================================================================
   ```
   Frame times depend on the machine; the tiers in §2 were measured on Apple Silicon (M3).
4. Run it live: click the eye in the menu bar and drop the file on a Space.
5. Submit it, if you like: open a pull request, or an issue with the "Theme submission" template,
   with the scorecard, the PNG and the mode you ran (zero-shot or agentic). See
   [CONTRIBUTING.md](CONTRIBUTING.md).
