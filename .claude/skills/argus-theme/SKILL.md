---
name: argus-theme
description: Write native, zero-allocation, 60fps Retina desktop wallpaper themes in Zig 0.17.0 for Argus.app without touching AppKit, and verify them with the headless theme harness.
---

# Argus Theme Authoring (`argus-theme`)

Use this skill whenever a user asks for a custom desktop wallpaper, animation, simulation, or visual theme in Argus (e.g., *"make my desktop feel like rain on a window"*).

## Why the Rules Are Strict (Protect the User's Machine)
Themes are compiled to `.dylib` and loaded via `dlopen` directly into the `Argus.app` wallpaper daemon, which drives every macOS Desktop Space:
- **Exactly 1 allocation at `init`, 0 after**: Put all simulation arrays and lookup tables inline as fixed-size fields inside `State` so `alloc.create(State)` is the single allocation. Per-frame allocations fragment the daemon heap across 216,000 frames/hour.
- **No clocks, sleeps, or I/O**: Never call `clock_gettime`, `sleep`, file I/O, or network APIs. Argus owns time: it pauses hidden Spaces, throttles on low power, and passes a fixed `dt: f64` (`0.008`) to `step`.
- **No panics or `unreachable` on runtime values**: An uncaught panic inside a `.dylib` kills the entire desktop wallpaper process across all Spaces. Guard divisions, clamp indices, and validate state via `hasNaN`.
- **16.67 ms frame budget**: A slow theme starves WindowServer compositing and heats the user's Mac.

---

## 1. The Stateful Theme Contract

Create `themes/<ThemeName>.zig` (with `// @argus-theme: custom_shader` in the header) importing `argus_theme_sdk.zig`:

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
        self.* = .{
            .w = w,
            .h = h,
            .scale = scale,
        };
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// Fixed-timestep state advance. Argus owns time (`dt` is 0.008 per frame).
    pub fn step(self: *State, dt: f64) void {
        self.time += dt;
    }

    /// Render into premultiplied RGBA8888 pixel buffer.
    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const h: usize = @min(self.h, buf.len / stride);

        for (0..h) |y| {
            const row = buf[y * stride .. y * stride + self.w];
            for (0..self.w) |x| {
                _ = x;
                row[x] = sdk.packRGBA(12, 18, 28);
            }
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

### The Three Traps That Break Themes Silently
1. **Pixel Format (`0xFF_BB_GG_RR` in little-endian `u32`)**:
   - CoreGraphics reads memory bytes `[R, G, B, A]` with `kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big`.
   - On Apple Silicon (little-endian), `R` is bits `0..7`, `G` is `8..15`, `B` is `16..23`, and `A` is `24..31`.
   - **Always use `sdk.packRGBA(r, g, b)` or `sdk.packPremulRGBA(r, g, b, a)`**. Raw `0xFFRRGGBB` swaps Red and Blue, and `alpha == 0` is rejected by the harness.
2. **The Stride Trap (`y * stride + x`, NEVER `y * w + x`)**:
   - `CGBitmapContext` pads rows to 64-byte boundaries (`stride >= w`). The harness surrounds row padding with canary values and fails if you write past `row[0..self.w]` or index with `y * w + x`.
3. **Dimensions & Scale**:
   - `w` and `h` are actual backing buffer pixels (`usize`). `scale` (`f64`) is the Retina backing scale factor (`2.0` on Retina).

---

## 2. Zig `0.17.0` Rules (Contradicts `0.13`–`0.15` Training Weights)

Argus compiles themes with **Zig `0.17.0`** (`./.toolchain/zig`, `$ZIG`, `$HOME/zig-toolchains/zig-0.17.0/zig`, or `zig` on `$PATH`).

- **Vector Splatting**: `@as(@Vector(4, f32), @splat(val))` — `[_]f32{val} ** 4` is a compile error on vectors.
- **Casts**: `@floatFromInt`, `@intFromFloat`, `@intCast`, `@ptrCast` (never `@intToFloat` or `@floatToInt`).
- **`std.mem` trimming**: `std.mem.trimEnd` / `std.mem.trimStart` (replacing `trimRight` / `trimLeft`).
- **Sentinel formatting**: `std.fmt.bufPrintSentinel(&buf, fmt, args, 0)` (replacing `bufPrintZ`).
- **Deep reference & example**: Read `docs/ZIG_017_DOSSIER.md` for `0.17.0` stdlib rules and `themes/Magnetar_Minimal.zig` for a complete reference theme.

---

## 3. Verification Loop: The Headless Harness

Never ask the user to debug a theme. Run the headless harness from the repository root:

```bash
make harness THEME=themes/<YourTheme>.zig
```

### Gate 1: Telemetry Contract (`Verdict : PASS`)
Treat a failing harness like a compile error. The harness enforces:
1. `Allocs at Init : 1` and `Allocs after Init : 0`.
2. `Stride Guard : CLEAN` (tested at both `stride = w + 16` with canary guards and `stride = w`).
3. `NaN / Inf Check : CLEAN`.
4. `Pixel Variance : > 256 non-bg pixels` and `alpha=0 count: 0`.
5. `Avg Frame Time <= 16667.0 us` (60 FPS budget).

### Gate 2: Visual Inspection (Necessary, Not Sufficient)
A passing harness only proves the theme doesn't crash, leak, or overrun stride. Before finishing:
1. View `/tmp/argus_theme_out.png` with your image viewing tool.
2. Verify the composition, color palette, lighting, depth, and motion cues genuinely match what the user asked for. If the frame looks flat, ugly, clipped, or empty, refine the rendering math and re-run `make harness` until both the telemetry and the visual output are exceptional.
