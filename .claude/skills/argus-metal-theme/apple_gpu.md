# The Apple GPU, as Argus drives it

How Apple-silicon GPUs work and what that means for Argus's engine: measured on an M3
(`make gpu-arch`, the harness, `make gpu-probes`) and checked against Apple's own material.
Tags: **[measured]** here, **[Apple]** stated by Apple, **[RE]** reverse-engineered by
others. Numbers are for an M3 at 1920x1200 unless noted; ratios travel better than
absolutes. Some measurements name themes that are no longer in `themes/` (Coral Reef,
Gemini Aquarium, Lizard Island); they are in the history: `git show f566e3a:themes/<name>`.

## 1. The machine

- **SIMD groups of 32 threads** run in lock-step on every Apple GPU [Apple]. A threadgroup
  is cut into consecutive runs of 32 threads, x first: in Argus's 32-wide groups a SIMD
  group is **one row of 32 pixels** [Apple, measured: per-row branches are free, per-pixel
  ones cost 2x].
- **Each core:** 128 ALUs, 4 schedulers, each issuing one instruction per cycle from one
  SIMD group [RE, Philip Turner's metal-benchmarks]. FP16 and FP32 run at the same rate on
  M1/M2 [RE] and on the M3 [measured]. Use `half` to save registers and bandwidth, not
  for speed.
- **No hardware integer divide** [Apple, WWDC16]. Dividing by a runtime value costs about
  58 µs per op per frame here, by a constant like 2049 about 15 µs, and by a power of two
  nothing [measured]. Prefer power-of-two strides, constants, or function constants.
- **Transcendentals** are a few FMAs each: `exp` ~1x, `sqrt`/`pow` ~2x, `sin` ~4x an FMA
  [measured; RE gives 4/8/14 cycles vs 2 for an FMA]. `sin` is already the fast version
  under Metal's default fast math; `precise::sin` costs 2.5x.
- **M3 Dynamic Caching** [Apple, WWDC23 "Explore GPU advancements in M3 and A17 Pro"]:
  registers, threadgroup memory and tile memory come from one on-chip pool allocated at
  run time, by what the code actually uses. So on an M3:
  - code that doesn't run doesn't cost (an unused coral path in Coral Reef: 0.02 ms)
    [measured];
  - reserving threadgroup memory (up to 28 KB) had no occupancy effect [measured];
  - threadgroup shape made no difference once the GPU was warm [measured].
  **M1/M2 have no Dynamic Caching.** There, the register count of the *worst path* sets
  occupancy for the whole kernel (about 208 KB of registers per core, 384–3072 resident
  threads [RE]), so big "uber" kernels like the reef themes may run noticeably worse than
  our M3 numbers suggest. Apple still recommends specializing with function constants over
  uber shaders (58 ms → 12.5 ms in its WWDC23 example) [Apple]. Measure on an M1/M2 before
  promising budgets.

## 2. Clocks: the number that matters is the paced one

The GPU's clock follows its load [Apple, WWDC21; RE: M1 runs 396–1278 MHz]. Argus is a
light periodic load: one frame every 33 ms. The GPU stays at a low clock, and **the same
frame takes ~1.9x longer than back-to-back** [measured, `make gpu-arch ARCH=clocks`]:

| Same frame | GPU time |
|---|---|
| back-to-back (benchmarks, the old harness numbers) | 0.67 ms |
| paced at 30 FPS (a visible Space) | 1.28 ms |
| paced at 10 FPS (a warm neighbour) | 1.28 ms |

The harness reports both (`Profile (BGRA8)` and `Paced 30 FPS`). Live costs of the
Metal themes are 1.4–2.3x their back-to-back numbers: Lizard Island 2.6 → 5.6 ms, Coral
Reef 3.3 → 5.9 ms, Aquarium 1.7 → 3.5 ms, Tides 0.6 → 1.5 ms. That is efficient (a low
clock is low power), but **budgets must be judged on the paced number**, and A/B tests
must warm the GPU first: two of the "wins" this study first found (compute 2x slower than
fragment, 32x32 groups 2.5x slower) were the GPU clock ramping up during the first
measurement.

## 3. Memory

- **Unified memory** [Apple]: CPU and GPU share it; bandwidth is ~100 GB/s on M2/M3,
  150–400 GB/s on Pro/Max. The system level cache is 8 MB on M1/M2 base, 24/48 MB on
  Pro/Max [RE]; there are no public M3 cache figures.
- **Coherent access is everything** [measured]: 32 coherent texture reads per pixel cost
  0.45 ms per frame; the same reads at random addresses in an 8 MB texture cost 33 ms.
- **State formats** [measured, 3x3 neighbourhood reads]: RGBA16F 0.41 ms, RGBA8 0.46,
  RGBA32F 0.63 ms (1.5x). A `half4` device buffer is as fast as a texture (0.47).
- **Threadgroup memory staging lost** to direct texture reads for a 3x3 neighbourhood
  (0.67 vs 0.41 ms): the texture cache already serves neighbours [measured]. Stage only
  when many threads reuse data the cache can't hold.
- **Lossless compression** [Apple]: textures are compressed only without `shaderWrite`
  (or `pixelFormatView`) usage. Argus's drawables are `framebufferOnly = false` and written
  by a compute kernel, so they are never compressed. Measured: a render target without
  ShaderWrite is written in 61 µs instead of 110 µs and read back in 52 µs instead of
  113–167 µs. The compositor reads every presented frame, so this is a per-frame
  bandwidth (and power) saving on every visible Space.

## 4. Render passes vs compute (TBDR)

Apple GPUs render in tiles held in on-chip memory: tile memory, imageblocks and tile
shaders exist **only inside render passes** [Apple, "Tailor your apps for Apple GPUs and
tile-based deferred rendering"]. A compute kernel never touches them. For Argus's
per-pixel shading the arithmetic costs the same either way (0.59 ms compute vs 0.62 ms
fragment, warm [measured]); the difference is the write: a fragment pass into a
`framebufferOnly` drawable (load don't-care, store) writes each tile once, compressed.

## 5. The CPU side

- Encoding and committing one frame (command buffer, compute encoder, `setBytes`, two
  textures, one dispatch) costs ~5 µs [measured]. Encoders are meant to be recreated every
  frame; pipelines, libraries and textures are made once [Apple] (Argus does this).
- So the 0.1–0.2 ms of CPU per Metal-theme frame is not encoding. The remaining candidates
  are `nextDrawable`, presenting, autorelease pools and the AppKit timer: profile those
  before optimizing anything on the CPU.

## 6. Frame pacing

Argus drives every Space from a 30 FPS `NSTimer` and presents each frame as soon as it's
drawn (`presentDrawable:`). Apple's guidance [Apple, CAMetalDisplayLink,
`NSView.displayLink`, `preferredFrameRateRange`, `presentDrawable:afterMinimumDuration:`]
is to pace from the display: request 30 FPS from a display link (rates snap to factors of
the refresh rate) and present at a minimum interval, so every frame stays on screen for the
same number of refreshes. A free-running timer drifts against a 120 Hz ProMotion panel:
frames then stay up for 3, 4 or 5 refreshes, which reads as judder in slow, smooth motion.
Not measured yet.

## 7. Structural upgrades this points to, in order

1. **Pace from the display**: display link at 30 FPS + `afterMinimumDuration` presents.
   Steadier motion, no theme changes.
2. **Present through a render pass** into a `framebufferOnly` drawable (a fragment wrapper
   around `argus_draw`, or a final full-screen pass): compressed frames, less bandwidth for
   Argus and the compositor.
3. **Function constants** for screen size and theme constants, so the compiler folds them
   (matters most on M1/M2, where the worst path sets occupancy).
4. **Test on an M1/M2.** Without Dynamic Caching the reef "uber" kernels may lose much
   more occupancy than on the M3.

Sources: Apple WWDC23 "Explore GPU advancements in M3 and A17 Pro"; WWDC21 "Discover Metal
debugging, profiling, and asset creation tools"; WWDC20 "Optimize Metal Performance for
Apple silicon Macs" and "Harness Apple GPUs with Metal"; WWDC16 "Advanced Metal shader
optimization"; developer.apple.com/documentation/metal ("Tailor your apps for Apple GPUs
and tile-based deferred rendering", "Optimizing texture data", MTLTextureUsage.shaderWrite,
CAMetalLayer.framebufferOnly, CAMetalDisplayLink); Philip Turner, github.com/philipturner/metal-benchmarks;
Asahi Linux, asahilinux.org/2022/11/tales-of-the-m1-gpu/.
