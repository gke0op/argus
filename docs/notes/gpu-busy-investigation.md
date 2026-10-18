# Why Argus looks like it keeps the GPU busy

Investigation of "over 50% GPU in the menu bar with ordinary use", October 2026.
Machine: M3 (10-core GPU), 8 GB, 3024×1964 built-in display, macOS 26. Argus main `fde32a6`,
the owner's seven-Space layout, `fps=30`, `smooth_swipes=1`. The owner's running Argus was never
stopped; every controlled run used this branch's own build with `--offscreen` (Space windows far
off-screen), stopped by its PID.

## Short answer

1. **The menu-bar "GPU %" is time, not work.** At Argus's pace the GPU never leaves its lowest
   performance state (P1, ≈338 MHz of a ≈1.34 GHz top clock). Every frame takes 2–3.4× its
   full-clock time there, so the same work shows up as 2–3.4× more "busy" time.
2. **The energy is small and is spent efficiently.** The whole GPU draws about 1.1–2 W with the
   owner's Argus, WindowServer, Finder and the other apps together. One Argus theme adds 0.3–1.4 W.
   Night Tide costs 43 mJ per frame at P1 against about 50 mJ at full clock (21–23 W for 2.5 ms),
   so running slowly is, if anything, cheaper. Making frames finish faster would lower the meter,
   not the energy.
3. **Argus is less than half of the "50%".** In a typical moment the GPU is active 55–61% of the
   time: Argus ≈20%, WindowServer ≈13%, Finder ≈8–9%, plus Claude, Spotify and others.
4. **Real savings come from doing less invisible work** (warm neighbours: ≈20% of Argus's own GPU
   time on the owner's layout) and from the themes' own per-pixel cost. Engine-wide knobs that
   change no pixel (threadgroup shape, batching) measured within noise.

## Method

| Number | Tool | What it is |
|---|---|---|
| per-process GPU % | `ioreg` IOAccelerator `AppUsage.accumulatedGPUTime`, delta / wall time (`tools/gpu_meter.py`) | exclusive GPU execution time of each process: Activity Monitor's %GPU |
| "Device Utilization %" | `ioreg` IOAccelerator `PerformanceStatistics` | what menu-bar GPU meters show: share of time the GPU is doing anything |
| GPU power (W), P-state residency | IOReport `Energy Model` and `GPU Stats/GPUPH` via ctypes on `/usr/lib/libIOReport.dylib` (`tools/gpu_meter.py`) | what `powermetrics` reports, without sudo |
| P-state frequencies | `ioreg -r -n pmgr` `voltage-states9` | P1 ≈ 338 MHz @ 640 mV … top ≈ 1.34 GHz @ 945 mV |
| GPU ms per frame in the app | command-buffer GPUStart/EndTime, `--perf-log` (`gpu_ms: s<N>=…`) | span of each frame's command buffer, including time sliced with other processes |
| marginal cost of a configuration | `tools/gpu_experiment.py`: `--offscreen --bench-space N` build vs an all-"macOS Default" baseline, alternating | GPU % and W added by one configuration |

No Xcode on this Mac, so no Instruments/xctrace Metal System Trace.

Background load during measurements: another session's `theme_harness` and a Zig test ran at
times and drove the GPU to its top states at 17–23 W; those samples are excluded (they are easy
to spot: the GPU leaves P1). `replayd` and ScreenTimeWidget used 0% (an earlier report said
otherwise; that was a parser bug, corrected).

## Measurements

### The live system (read-only, owner's Argus running)

3-minute time series, 2 s samples, low-power samples only (66 of 74):

| | mean |
|---|---|
| Device Utilization (menu bar) | 53% |
| GPU active residency | 61% |
| share of active time at P1 | 68% (the rest P2–P3) |
| GPU power | 1.8 W |
| Argus GPU | 20% |
| WindowServer GPU | 13% |
| Finder GPU | 9.3% (and ≈30% CPU) |

### One theme at a time (off-screen build, Space 0 drawn at 30 FPS, GPU at P1 throughout)

| Theme | Argus GPU % | GPU ms per frame (÷30) | back-to-back at full clock | ratio | marginal GPU W |
|---|---:|---:|---:|---:|---:|
| Tutorial_Tides | 6.4 | 2.1 | 0.63 | 3.4× | +0.26 |
| Tutorial_Reef | 10.0 | 3.3 | 1.1 | 3.0× | +0.67 |
| Ebru_Studio | 10.2 | 3.4 | 1.0 | 3.3× | ≈0 (noise) |
| Orion_Nebula | 12.3 | 4.1 | 1.7 | 2.4× | +0.75 |
| Cygnus_A (GPU, HDR10, native) | 10.8 | 3.6 | 1.6 | 2.3× | +0.57 |
| Night_Tide | 23.5 | 7.8 | 2.5 | 3.1× | +1.28 |
| Lizard_Island | 19.3 | 6.4 | 3.0 | 2.1× | +1.38 |

Baselines between cases: 1.1–2.0 W (the owner's Argus, WindowServer, Finder, other apps).

### Energy per frame, slow vs fast

Night Tide back-to-back (P13, top state ≈90% of active time): 21–23 W GPU. At ≈2.5 ms a frame that
is ≈50 mJ per frame. At 30 FPS (P1): +1.28 W ÷ 30 = 43 mJ per frame.

### Warm neighbours (owner's layout, Lizard Island active, Reef and Orion as neighbours)

| | Argus GPU % | marginal W |
|---|---:|---:|
| warm off | 19.3 / 20.2 | 1.45 / 1.57 |
| warm on (10 FPS) | 24.0 / 23.9 | 2.09 / 1.63 |

Warm neighbours add ≈4 points, ≈20% of Argus's own GPU time; power within noise to +0.6 W.

### Engine knobs that do not matter

- **Threadgroup shape** (draw dispatch, themes without threadgroup memory: Night Tide, Ebru,
  Reef, Tides): 32×8, 16×16, 32×4, 64×4 vs the default 32×32 — within run-to-run noise (Night Tide
  2–3% at best). Not worth changing.
- **Command buffers per frame:** one per Space per frame, one compute encoder, compute writing
  the drawable directly. Batching Spaces into one submission cannot remove GPU wake-ups: Spaces
  drawn in the same tick are already submitted back to back.

## Findings (why)

1. **DVFS keeps a periodic light load at P1.** A 30 FPS wallpaper is the textbook load the
   governor serves from its lowest state: a few ms of work every 33 ms never justifies raising the
   clock. The work is stretched 2–3.4× in time and "busy" goes up by the same factor, while
   voltage (and so energy per cycle) is at its lowest. The menu-bar percentage measures occupancy,
   and occupancy at 338 MHz is not comparable with occupancy at 1.34 GHz.
2. **The real cost is per-pixel work.** 0.6–3 ms of full-clock GPU per frame per theme, at
   1920×1200 (Cygnus A at 3024×1964). Night Tide and Lizard Island are the expensive ones.
3. **Invisible frames:** warm neighbours draw two hidden Spaces at 10 FPS each. Step-driven
   themes are frozen while hidden anyway, and a warm neighbour already shows a frame up to 100 ms
   old when a swipe begins, so the frames buy no smoothness that pausing would not give.

## Fixes, ranked by measured gain

| # | Fix | Measured | Picture | Status |
|---|---|---|---|---|
| 1 | Pause hidden Spaces, resume one frame later (no jump) — makes "Smooth swipes" off seamless; recommend off | −20% of Argus GPU time on the owner's layout (more when neighbours are heavy) | the visible Space is unchanged; a swiped-in Space continues from its last frame instead of jumping 0.1–0.5 s | resume committed (eb96dc5); turning the setting off is the owner's call |
| 2 | Per-theme kernel work: Night Tide, Lizard Island | 2.5–3 ms of 0.6–3 ms per frame | must stay image-identical | theme sessions; not engine |
| 3 | Read "W" rather than "GPU %": the meter overstates by 2–3.4× at P1 | — | — | documentation |

Pending: whether Argus's animated wallpaper is what keeps Finder redrawing the desktop
(≈30% CPU, ≈9% GPU; correlation with Argus 0.81) and what WindowServer's 13% contains. That needs
a 90-second test with Argus paused on screen, requested through Argus I.
