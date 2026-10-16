# The Quasars

*Five black holes on your desktop: four of them real, all of them computed.*

A quasar is a supermassive black hole caught in the middle of a meal. Gas spirals in, rubs
against itself, heats past 30,000 degrees and outshines its whole galaxy. No telescope can
see one up close; they are far too small and far too distant. What we know comes from their
light: its colours, its flicker, and the way gravity bends it.

Argus draws what that physics predicts you would see if you were there. Nothing in the image
was painted. The shadow, the glowing ring, the arc of light wrapped over the top: each one
falls out of Einstein's equations, solved for every pixel of your screen.

---

## What you are looking at

- **The black shadow.** Light that comes too close never escapes. The shadow is roughly two
  and a half times wider than the black hole's horizon, because gravity bends the light skimming
  past it.
- **The lopsided "D" shape.** The black hole spins and drags space around with it. Light
  moving with the spin gets closer before it is caught, so one side of the shadow is flattened.
- **The arc over the top, and the one underneath.** That is the far side of the disk, behind
  the black hole, with its light bent up over the top and down under the bottom. You are seeing
  the back of the disk *through* the gravity of the hole.
- **One side brighter than the other.** The disk orbits at a large fraction of the speed of
  light. The side coming toward you is boosted brighter and bluer, the side moving away is
  dimmed and reddened.
- **The thin bright rings hugging the shadow.** Light that looped around the hole once, twice,
  more, before reaching you. Each ring is a fainter, thinner copy of the whole disk.
- **The blue streaks (the "eyeliner").** Clumps of hotter gas, stretched into arcs because the
  inner disk orbits faster than the outer disk. Hotter gas reads bluer.
- **The dark band.** The cold, faint outer disk seen nearly edge-on, across the front.
- **The black sky.** Next to a quasar the stars are about a trillion times fainter. Any exposure
  that shows the disk shows them as black.

---

## The lineup

| Theme | Modelled on | What is real | What is chosen |
|---|---|---|---|
| **Opus Quasar** | H1821+643, the quasar at the heart of a galaxy cluster | Spin 0.62 (X-ray), mass ~4 billion Suns, feeding at ~20% of its limit | The 88° camera; the disk drawn thin |
| **Opus Cygnus A** | Cygnus A, the hidden quasar inside the most famous radio galaxy | Mass 2.5 billion Suns (gas dynamics), feeding at ~1% | Spin 0.9 (never measured: dust hides it) |
| **Opus J0834** | F2MS J0834+3506, a young, dust-reddened "red quasar" | Mass 3.2 billion Suns, feeding at 4% | Spin 0.99 from published models, not a direct measurement |
| **Opus PG1426** | PG 1426+015, the heaviest black hole weighed by light echoes | Mass 1.0 billion Suns, spin above 0.7 (X-ray) | Spin set to 0.9 inside that range |
| **Opus Gargantua** | The black hole from *Interstellar* | The same computed light paths and spin physics | Its disk is tuned to a cinematic 6,500 K glow |

Each theme's header lists its sources. Three of the real quasars feed slowly enough
(1–4% of their limit) that their disks are genuinely razor-thin, which is what makes the
edge-on view honest. H1821+643 eats faster; see "Known approximations" below.

---

## How faithful is it? A hierarchy, stated plainly

Not everything here is equally exact, and we say which is which.

### 1. Computed exactly, and checked against known answers
- **Every light path.** Each pixel's light is traced backward through the curved spacetime of a
  spinning black hole (the Kerr solution), with no shortcuts.
- **The shadow's outline.** Compared at 766 points against the analytic curve Bardeen derived in
  1973: the largest error is 1.1×10⁻⁵ of the black hole's mass unit. On a Retina screen that
  is **under 1/2000 of a pixel**.
- **Redshift, beaming, the innermost stable orbit, the photon rings, frame dragging.** These
  come out of the same equations; none is drawn by hand.

### 2. Computed from a physical model
- **The disk itself.** Its density, temperature and transparency all come from one solution of
  the general-relativistic equation for how a disk of gas spreads and feeds the hole (Balbus
  2017; Mummery & Balbus 2019), with a standard friction law (α = 0.1). They are not separate
  knobs.
- **Its glow.** Thermal light at each radius, hardened the way scattering atmospheres harden it
  (Done et al. 2012), darkened toward the limb (Chandrasekhar's scattering atmosphere), turned
  into colour with the 1931 CIE colour-matching functions.
- **The shimmer.** Turbulence with the measured statistics of magnetised disk turbulence (eddy
  shapes, sizes and lifetimes from published simulations), not a full simulation of it.

### 3. Known approximations (each one disclosed in the code and the dossier)
- **The disk is a moment in time.** It is a ring of gas caught while still spreading, not the
  steady disk a real quasar keeps for millions of years. This is what gives the outer fade and
  the dark band. A steady disk would fill the frame with glowing gas.
- **The disk is drawn infinitely thin.** True for the slow eaters (Cygnus A, PG 1426). H1821+643
  and J0834 would really be somewhat puffier, enough to change the edge-on view.
- **The colour correction is a fit** to the peak of real disk spectra, applied across visible
  light. It slightly overstates how bright one ring of the disk looks.
- **Not drawn:** the hot corona above the disk, the jets, light the disk shines back onto
  itself, polarisation.

### 4. Chosen, for the picture
- The camera: 88° from the spin axis (nearly edge-on), 1000 mass units away, the zoom.
- Time is sped up so the motion is visible: each second on screen is 10 light-crossing times
  of the hole: about a day and a half for Cygnus A, two days for H1821+643 (~100,000–200,000×
  real time).
- The hot spots' number, size and brightness (their motion is computed).
- Exposure and tone mapping, so a disk at tens of thousands of degrees fits on a screen.

---

## How it was checked

- **A test ledger.** Every physics claim the code makes is a test with a reference and a
  tolerance, written to [`opus_quasar_ledger.json`](opus_quasar_ledger.json): 56 records,
  49 pass, 0 fail, 7 reported values. Regenerate it with `make ledger`.
- **Two independent renderers.** A double-precision CPU path and a single-precision GPU path
  trace the same scene; they agree on 97% of pixels to within 8 levels, and on the shadow edge
  to 10⁻⁵.
- **Outside review.** The model was audited by independent AI reviewers from several model
  families (Gemini, GPT, Claude, DeepSeek, Nemotron and others; an overnight panel returned
  reports from 7 of the 11 models tried). Every finding was re-derived before it was accepted:
  23 were confirmed and fixed or disclosed, and the rejected ones are recorded with the reason.

### Reproduce it

```sh
make test                                   # unit tests + generated-theme check
./.toolchain/zig test themes/Opus_Quasar.zig  # the physics claims, printed as ledger records
make ledger                                 # rebuild docs/opus_quasar_ledger.json
make gpu-bench BH_THEME=themes/Opus_Quasar.zig  # GPU vs CPU, shadow contour, timings
make quasars                                # regenerate the quasar family from Opus_Quasar.zig
```

The four real quasars share one engine: `themes/Opus_Quasar.zig`. The others are generated
from it by `tools/gen_quasars.py` with their own mass, spin, feeding rate and sources. Adding a
quasar is one entry in that table.

---

## Is this what a quasar *really* looks like?

As close as the physics in the hierarchy above allows, and no closer. The light paths are
exact. The disk is a physically consistent model with its approximations on the table. The
camera is a choice: from Earth we see H1821+643 at about 45°, not edge-on, and no instrument
could resolve it.

It is not the Event Horizon Telescope's picture of M87* or Sgr A*. Those black holes are
starving: their gas is hot, thin and see-through. A quasar is the opposite, a feeding black
hole wrapped in a bright, opaque disk.

Argus brings research-style relativistic ray tracing into real-time desktop rendering. Its
validation results are listed above so you can judge it on them.

---

## Where you could help

The approximations above are the roadmap: a steady disk with a physical outer edge, finite
disk thickness, full radiative transfer through the disk atmosphere, the corona and the jets.
Each would make the picture more true. Some of them would also change the look; when they
do, the plan is to keep them as switches rather than replace what is there.

---

## For physicists

The full derivations, numbers and review history are in the dossier,
[`docs/majestic-glutton.md`](majestic-glutton.md): the geodesic integrator and camera, the disk
equation and its closures, the vertical structure and opacities, the radiation model, the
turbulence statistics, the hot spots, every check and every approximation.

<details>
<summary>Key references</summary>

- Kerr light paths and the shadow: Bardeen, Press & Teukolsky 1972; Bardeen 1973; Carter 1968.
- Disk evolution: Balbus 2017; Mummery & Balbus 2019, MNRAS 489, 132. Steady disk: Page &
  Thorne 1974; Shakura & Sunyaev 1973.
- Colour correction: Done, Davis, Jin, Blaes & Ward 2012. Limb darkening: Chandrasekhar 1960;
  Laor 1991.
- Turbulence statistics: Guan et al. 2009; Beckwith, Armitage & Simon 2011; Hirose et al. 2009.
- H1821+643: Sisk-Reynés et al. 2022 (spin); Fukuchi, Ichikawa et al. 2022 (Eddington ratio);
  Li et al. 2026, arXiv:2601.18269 (reverberation); Robinson et al. 2010 and Jadhav et al. 2021
  (recoil candidate).
- Cygnus A: Tadhunter et al. 2003 (mass); Privon et al. 2012 (luminosity).
- F2MS J0834+3506: Piotrovich, Buliga & Natsvlishvili 2024, arXiv:2410.04851.
- PG 1426+015: Walton et al. 2025, arXiv:2509.13411.

</details>
