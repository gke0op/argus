---
name: argus-cpu-port
description: Port an Argus Metal theme to the CPU (themes/cpu/, run by argus_kernel.zig) so it runs on Linux, in VMs and without a GPU, then verify it against the original and make it fast. Use for any work on themes/cpu/ or the Linux host (src/argus_linux.zig).
---

# Porting a Metal theme to the CPU (`argus-cpu-port`)

`themes/cpu/argus_kernel.zig` runs an Argus kernel the way a GPU does: one call shades N
neighbouring pixels, one per SIMD lane (16 with AVX-512, 8 with AVX2, 4 with SSE or NEON), and
rows are shared out to every core. A port is an ordinary Zig theme: the harness, Argus.app and
`argus-linux` load it unchanged. `themes/cpu/Tutorial_Tides.zig` is the reference port; read it
next to `themes/Tutorial_Tides.metal` before writing one.

**Scope today:** draw-only kernels (`argus_draw`). Not yet supported: state textures
(`argus_init` / `argus_step`, `// @argus state`), threadgroup memory and barriers, atomics,
samplers, `@argus stats`. Of the shipped themes, Tutorial_Tides is ported; Orion_Nebula is
draw-only but uses threadgroup memory. Extending the executor is engine work: add the feature to
`argus_kernel.zig` with a test, then port.

## Translation

| Metal | Port |
|---|---|
| `float` | `F` (one value per lane); constants `f(0.5)` (Zig never splats a scalar into a vector) |
| `float2`, `float3` | `V2`, `V3` (one `F` per component); constants `v2(..)`, `v3(..)` |
| `a * b` on float3 | `a.mul(b)`, `a.scale(s)`, `a.add(b)`; `V3.mix(a, b, t)`, `.saturate()` |
| `if (c) x = a; else x = b;`, early `return` | `sel(c, a, b)`, `V3.select(c, a, b)`: every lane runs both sides, as on a GPU |
| `argus_uv`, `argus_noise`, `argus_fbm`, `argus_rand`, `argus_palette`, `argus_srgb`, `argus_aces` | `uv`, `noise`, `fbm`, `rand` (with `cell(p, k)`), `palette`, `srgb`, `aces` |
| `sin`, `cos`, `exp`, `exp2`, `log2` | same names (SIMD polynomials, ~2e-7) |
| `kernel void argus_draw(...)` writing `out` | `pub fn draw(fr: *const k.Frame, gid: k.Gid) V3` returning the colour |

Keep the original's functions, constants and comments in the same order, so the two files can be
read side by side. End the file with `comptime { k.exportKernelTheme(@This()); }`.

## Rules that have bitten ports
- **Branches become selects; keep discarded lanes finite.** A lane whose result is thrown away
  still computes: clamp its inputs (Tides clamps `depth` at 0 so sky lanes never divide by ~0).
  A NaN reaching `@intFromFloat` (inside `cell`, `noise`) is undefined behaviour.
- **Share one expensive call between branches** when the GPU original calls it on both paths
  (Tides: one `sky()` call at a per-lane point, sky or mirrored sea), instead of two selects.
- **Struct-literal aliasing:** `p = .{ .x = .., .y = ..p.x.. }` writes `p.x` before `.y` reads
  it. Build into a temporary, then assign.
- **Float mode:** the executor's helpers run optimized; `fbm` and the angle reduction in
  `sin`/`cos` are deliberately strict (fused or reordered math there changed results, and would
  differ between AVX and NEON). Adding `@setFloatMode(.optimized)` to the port's own hot functions
  gains ~5%; leave it out of anything that feeds coordinates into `noise` at large magnitudes.

## Verify (in this order)
1. `zig test themes/cpu/argus_kernel.zig` after any executor change (math accuracy, bit-exact
   prelude in every lane, pixel packing). `make test` also runs it as aarch64 under qemu when
   `qemu-aarch64-static` is installed: the 4-lane path Apple silicon takes.
2. `make harness THEME=themes/cpu/<Name>.zig OUT=/tmp/cpu.png`: every gate except possibly the
   frame budget on a small VM (`make check-themes CHECK_ARGS=--no-budget`).
3. **Parity with the original (on a Mac):** render both at the same frame count and diff:
   `make harness THEME=themes/<Name>.metal FRAMES=30 OUT=/tmp/gpu.png` and the same for the port.
   Look at both images; report max per-channel difference and the share of pixels more than 1
   level off. Tutorial_Tides: not yet compared against the GPU (no Mac in the porting session).
4. **Regression oracle when optimizing:** save the port's PNG before an optimization and diff
   every faster version against it. Tides holds max 1 level against its first scalar version.

## Make it fast
- `make linux THEME=... && ./argus-linux` prints ms per stage at exit (step, draw, upscale,
  wait, fill, send). Optimize the biggest; on kernel themes it is `draw`.
- Profile on Linux: `perf record -e cpu-clock -F 4000 ./bin`, then `perf annotate`: everything
  inlines into `Job.run`, so read it per instruction. Tides: 44% integer hashing (the prelude's
  hash, which must stay bit-exact with Metal), 40% float math.
- Build level matters more than anything in the port: Tides at 1920x1200 takes 166 ms with
  plain x86_64, 40 ms with `CPU=x86_64_v3` (AVX2), 21 ms native on AVX-512.
- `argus-linux` drops to 1/2 to 1/4 internal resolution when a theme is over budget and upscales
  straight into display memory; `--render-scale N` forces it.

## The Linux host in one paragraph
`src/argus_linux.zig` compiles one theme in, opens the X11 socket itself (`src/linux/x11.zig`,
no libX11), maps a desktop-type window on every workspace and presents through MIT-SHM. Kernel
themes draw straight into the shared frame in X's channel order (`argus_theme_draw_target`); SDK
themes draw [R, G, B, A] and are reordered (2.4 ms per 1080p frame), unless they also
export `pub export fn argus_theme_draw_target` (Reservoir_Field does: it repacks its colour table
to the target's channel offsets). Test it headless: `Xvfb :99 &`, `openbox &`,
`DISPLAY=:99 ./argus-linux --frames 300`, screenshot with `xwd -root`. Wayland and GNOME's default
session are not supported yet.

The theme runs caged (`src/linux/cage.zig`): in its own process with no X socket, under a
seccomp allowlist and Landlock (`src/linux/sandbox.zig`), talking to the host through shared
memory and a futex. A port therefore must not open files or sockets, fork or exec, not even in
`init` (all fail with EPERM); threads are fine. AMX permission (`arch_prctl` XCOMP_PERM) is
allowed. A caged call costs ~0.1-0.3 ms per frame (an idle vCPU takes ~100 us to wake).
`tests/fixtures/Fixture_Hostile.zig` must stay at 0 escapes and 0 reachable descriptors.
