---
name: argus-theme
description: Write native, zero-allocation desktop wallpaper themes in Zig 0.17.0 for Argus.app (CPU themes via themes/argus_theme_sdk.zig), held to the same quality bar and render-critique loop as the Metal themes, and verified with the headless theme harness. Use when a theme needs small, sequential, branchy CPU state; for everything else prefer argus-metal-theme.
---

# Argus Theme Authoring in Zig (`argus-theme`)

Most new themes should be Metal kernels (`argus-metal-theme` skill): they're faster and cost
~0 CPU. Write a Zig theme when the work is small, sequential, branchy state the GPU can't help
with: a 120-neuron reservoir with online learning, an oscillator lattice with non-local
coupling, or Cygnus A's CPU-built geodesic tables.

## 0. The bar, and when you are done

**The harness proves a theme runs. It does not prove the theme is good.** Every theme in the
October 2026 factory batch passed it, and the owner called them "at best sub par". Before
writing code, read [`../THEME_CRAFT.md`](../THEME_CRAFT.md): the bar, the 10-step workflow,
the A1–A10 critique checklist, the factory failure modes, worked examples (Cygnus A is
the shipped Zig one) and the honest-header template.

A theme is **done** when every one of these is true:

- [ ] **Subject and research.** A specific subject, a notes file with *how it looks* and *why*,
      sources tagged `[cited]`/`[snippet]`/`[data]`.
- [ ] **Look targets.** 5–10 checkable statements, each verified on the final renders.
- [ ] **Contact sheet.** `tools/theme_sheet.sh themes/<Name>.zig` was run, and every moment and
      the 1:1 crop were opened.
- [ ] **Critique.** A written A1–A10 critique of the final renders, with nothing left you would
      point at as wrong.
- [ ] **Motion.** Rates designed in human time; flicker measured, and you know what causes it;
      still alive after long runs (a reservoir theme was designed for days: RLS without
      forgetting, because forgetting overflows after minutes).
- [ ] **Claims.** Every number in the header is cited or checked with `sdk.ledger` tests (§4);
      every thing the header names is visible; known defects are fixed, not just disclosed.
- [ ] **Review.** An independent reviewer (fresh agent or the owner) saw the renders and the
      header, and its findings are resolved. If the owner hasn't seen it, the hand-off says so.
- [ ] **Header and cost.** Honest header; harness PASS on a quiet machine, or the cost given as a
      ratio to a control theme (`Cygnus_A.zig`) run alongside it if you can't quiet the machine.
- [ ] **Field notes.** An entry in [`../FIELD_NOTES.md`](../FIELD_NOTES.md).

## Why the rules are strict

Themes compile to a `.dylib` loaded with `dlopen` into the Argus wallpaper process, which
drives every Space:
- **1 allocation at `init`, 0 after.** Put all arrays and tables inline in `State`, so
  `alloc.create(State)` is the only allocation.
- **No clocks, sleeps or I/O.** Argus owns time: it pauses hidden Spaces, throttles on low
  power, and passes a fixed `dt` (`0.008`) to `step`.
- **No panics or `unreachable` on runtime values.** A panic in the `.dylib` kills the wallpaper
  on every Space. Guard divisions, clamp indices, and report bad state through `hasNaN`.
  ReleaseFast wraps integer overflow silently, so narrowing bugs (`@min(N, x)` inferring a `u10`)
  hide there. One theme caught such a bug only by sweeping sizes in ReleaseSafe.
- **Frame budget.** The harness fails above 16.7 ms average per frame. A slow theme starves
  WindowServer and heats the Mac, so aim far below it.

## 1. The stateful theme contract

Create `themes/<Name>.zig` (with `// @argus-theme: custom_shader` in the header) importing
`argus_theme_sdk.zig`:

```zig
// @argus-theme: custom_shader
const std = @import("std");
const sdk = @import("argus_theme_sdk.zig");

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time: f64 = 0.0,
    // Keep all lookup tables / particle arrays inline in State so init() does exactly 1 allocation.

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.* = .{ .w = w, .h = h, .scale = scale };
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// Fixed-timestep state advance. Argus owns time (`dt` is 0.008 per step).
    pub fn step(self: *State, dt: f64) void {
        self.time += dt;
    }

    /// Render into a premultiplied RGBA8888 pixel buffer.
    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const h: usize = @min(self.h, buf.len / stride);
        for (0..h) |y| {
            const row = buf[y * stride .. y * stride + self.w];
            for (row) |*px| px.* = sdk.packRGBA(12, 18, 28);
        }
    }

    /// Return true if any simulation float became NaN or Inf.
    pub fn hasNaN(self: *const State) bool {
        return !std.math.isFinite(self.time);
    }
};

comptime {
    sdk.exportTheme(State);
}
```

The skeleton compiles and passes the memory and stride gates, but it fails the variance and
motion gates until it draws something that moves.

### Three traps that break themes silently
1. **Pixel format: `0xAA_BB_GG_RR` in a little-endian `u32`.** CoreGraphics reads bytes
   `[R, G, B, A]` (premultiplied last, 32-bit big-endian order), so on Apple Silicon R is bits
   0..7 and A is bits 24..31. **Always use `sdk.packRGBA(r, g, b)` or
   `sdk.packPremulRGBA(r, g, b, a)`.** A raw `0xFFRRGGBB` swaps red and blue, and the harness
   rejects `alpha == 0`.
2. **Stride: `y * stride + x`, never `y * w + x`.** Rows are padded to 64 bytes. The harness
   puts canaries in the padding and fails if you write past `row[0..self.w]`.
3. **Dimensions and scale.** `w` and `h` are backing-buffer pixels; `scale` is the Retina factor
   (2.0 on Retina). Size features in points × `scale`, or they halve on Retina.

**Colour space:** the buffer takes display-encoded 0..255. If you light in linear light,
convert at the end, once. Don't type display-space constants into linear maths.

## 2. Zig 0.17.0 rules (they contradict 0.13–0.15 training data)

Argus compiles themes with **Zig 0.17.0**: `./.toolchain/zig`, then `$ZIG`, then `zig` on
`$PATH`. In a git worktree there's no `.toolchain`, so pass `ZIG=<main checkout>/.toolchain/zig`.
`std.process has no member Init` means you're on the wrong Zig.

- **Vector splat:** `@as(@Vector(4, f32), @splat(val))`; `[_]f32{val} ** 4` is a compile error on vectors.
- **Casts:** `@floatFromInt`, `@intFromFloat`, `@intCast`, `@ptrCast` (never `@intToFloat` / `@floatToInt`).
- **`std.mem`:** `trimEnd` / `trimStart` (not `trimRight` / `trimLeft`).
- **Sentinel formatting:** `std.fmt.bufPrintSentinel(&buf, fmt, args, 0)` (not `bufPrintZ`).
- **One declaration per statement:** `var a: f64 = 0, b: f64 = 0;` fails with "expected ';' after statement".
- **Tests on literals:** `std.testing.expectApproxEqRel(1.0, x, t)` with a comptime literal fails
  ("Cannot approximately compare two comptime_float values"); assign `const x: f64` first.
- **Imports:** a theme can't import from `src/` ("import of file outside module path"). Use what
  `themes/argus_theme_sdk.zig` provides.
- A complete shipped Zig theme, with tests and a claim ledger: `themes/Cygnus_A.zig` (large;
  the skeleton above is the small one).

## 3. Verification: the harness and the render loop

```bash
make harness THEME=themes/<Name>.zig FRAMES=300 OUT=/tmp/<name>.png
tools/theme_sheet.sh themes/<Name>.zig        # moments, 1:1 crop, flicker: every round
```

**Gates (`Verdict : PASS`).** Treat a failure like a compile error:
1. `Allocs at Init : 1` (stateful) and `Allocs after Init : 0`.
2. `Watchdog 320x200 : PASS`: no size assumptions.
3. `Stride Guard : CLEAN`, at `stride = w + 16` with canaries and at `stride = w`.
4. `NaN / Inf Check : CLEAN`.
5. `Pixel Variance` > 100 distinct pixels, and `alpha=0 count: 0`.
6. `Temporal Motion` ≥ 2,000 animated pixels between the first and last frame.
7. `Avg Frame Time` < 16,667 µs.

**Then the part that matters.** A PASS proves the theme doesn't crash, leak or overrun the
stride. It says nothing about whether it's good. Run the sheet, open every image and the 1:1
crop, critique them in writing against your look targets and A1–A10 in THEME_CRAFT.md, fix the
worst item, and repeat. Expect 10–20 rounds. Harness frames are `dt = 0.008` steps, so frame
2700 is 21.6 s of theme time; raise `MOMENTS` to see later. Run a ReleaseSafe build across a
few sizes before shipping, since ReleaseFast hides overflow.

## 4. Claim checks

Physics claims go in `test` blocks (in the theme or `themes/<Name>_claims.zig`) that record each
check with `sdk.ledger(.{ .id, .claim, .reference, .conditions, .quantity, .measured, .lo, .hi,
.source })` and assert its verdict. Each prints a `LEDGER {json}` line. Re-derive the reference
independently (closed form, paper, separate code), then audit your own discretisation against
it. `themes/Cygnus_A.zig` is the full pattern, collected by `make ledger` into
`docs/cygnus_a_ledger.json` and audited by two model families.

## When you are done: leave field notes

Append an entry to [`../FIELD_NOTES.md`](../FIELD_NOTES.md): what helped, what was wrong or
missing, what cost you time. Report how it *looks* (your critique, the owner's verdict), not only
the harness numbers.
