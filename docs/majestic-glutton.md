# Majestic Glutton: a physical model of the quasar H1821+643

*Working title of the Argus wallpaper `themes/Opus_Quasar.zig` (name may change). This document
states what the renderer computes, from which equations and numbers, how it was checked, and
what is chosen rather than computed. It is meant for review: please check the physics, not
the code style. Numbers are from the code and its tests at commit `dd1cbf6`; §3 and §9 are from
the test ledger [`docs/opus_quasar_ledger.json`](opus_quasar_ledger.json), which names its own
commit.*

Units: G = c = M = 1 unless stated. M = mass of the black hole. For M = 4e9 Msun:
1 M of length = 5.91e12 m (39.5 AU), 1 M of time = 19,700 s.

---

## 1. The object

H1821+643 (also E 1821+643) is a luminous quasar at z = 0.297, at the centre of the cool-core
galaxy cluster CL1821+643. We render it up close, as no telescope can: a supermassive Kerr
black hole fed by a thin, hot accretion disk.

| Parameter | Value used | Literature | Source | Status |
|---|---|---|---|---|
| Spin a* | 0.62 | 0.62 (+0.22 / −0.37, 90%) | Sisk-Reynés, Reynolds, Matthews & Smith 2022, MNRAS 514, 2568 (Chandra X-ray reflection) | measured |
| Mass | 4e9 Msun | ~3–6e9 (Hβ virial, UV disk fit, X-ray); outliers 1e9 and 3e10; 2026 reverberation lag in tension | Reynolds 2014 (arXiv 1408.4803); Fukuchi, Ichikawa et al. 2022 (arXiv 2209.09255) | centre of consistent estimates |
| Luminosity | 0.20 L_Edd (computed, see §4) | λ_Edd = 0.18 (full SED fit), 0.59 (X-ray bolometric) | Fukuchi, Ichikawa et al. 2022 | matches |
| Inner-disk inclination from Earth | (camera at 88°, a choice) | 44.6 ± 3.3° (90%); older fit ~57° | Sisk-Reynés 2022; Reynolds 2014 | our camera is not on Earth's line of sight |
| Radio | no jet drawn | radio-quiet by luminosity; weak FR I-type jet, lobes ~280 kpc | Blundell & Rawlings 2001 (astro-ph/0110157) | invisible in optical; outside the view |
| Recoil | not modelled | broad lines offset ~1000–2100 km/s; nucleus offset from host centre: candidate recoiling black hole | Robinson et al. 2010; Jadhav et al. 2021, MNRAS 507, 484 | unsettled; would look the same up close |

## 2. Camera

- Pinhole camera at r = 1000 M (0.19 pc), inclination 88° from the spin axis (nearly edge-on).
- Field of view: half-height 24 M on screen.
- Time-lapse: 10 M of coordinate time per unit of Argus dt. One ISCO orbit lasts ~5 s on screen;
  in reality it takes 11.3 days.
- Rendering: the GPU traces every pixel at native resolution (2×2 samples, 8×8 near edges and
  photon rings) and outputs HDR10. The CPU fallback is the reference implementation and the
  test harness.

## 3. Light paths

- **Geodesics:** exact Kerr null geodesics in Boyer–Lindquist coordinates, Hamiltonian form,
  integrated with RK4. p_r is re-solved from the null condition at every step; rays are traced
  backward from the camera.
- **Shadow test (full contour):** the traced shadow edge is compared with Bardeen's analytic
  critical curve at 766 points, at the theme's spin (0.62), inclination (88°) and camera
  distance (1000 M).
  - Samples: 510 over the whole curve (both halves; photon-orbit radius from the prograde to
    the retrograde end, spaced as (1 − cos πu)/2 so they are dense where the curve meets the
    equator), plus 256 in the polar band |α| < 0.004 M (see below).
  - Each edge is bisected along the ray from the shadow's centre (the shadow is convex), 32
    times, to 2e-10 M. The error is the radial offset along that ray, an upper bound on the
    distance to the curve.
  - The same samples run on the CPU (f64, `zig test themes/Opus_Quasar.zig`) and the GPU
    (f32, the Metal probe kernel, `make gpu-bench`). Tolerances were set before measuring.

  | Path | max, all points | max off-axis | RMS, curve sweep | RMS off-axis | max, polar band |
  |---|---|---|---|---|---|
  | CPU f64 | 8.2e-3 M | 7.6e-6 M | 1.5e-4 M | 2.7e-6 M | 8.2e-3 M |
  | GPU f32 | **1.7e-2 M (fails)** | 7.8e-5 M | 1.3e-4 M | 7.3e-6 M | 1.7e-2 M |
  | Tolerance | 1e-2 M (¼ pixel) | 1e-4 M | 1e-3 M | 1e-4 M | reported |

  - **Off the spin axis** the ray solver matches the critical curve to < 1e-5 M on the CPU and
    < 1e-4 M on the GPU, over the whole contour.
  - **On it (found by the sweep):** rays with angular momentum L ≈ 0 (|α| ≲ 0.002 M) pass close
    to the spin axis, where Boyer–Lindquist coordinates are singular and the step control is too
    coarse. The edge there is off by up to 8.2e-3 M (CPU) and 1.7e-2 M (GPU, 0.4 pixel). The
    band is ~1/20 of a pixel wide, at the top and bottom of the shadow.
  - The GPU's polar maximum fails the ¼-pixel tolerance: the one failing record in the ledger.
    It was always there. The old 11-point test (worst 7.5e-6 M) never sampled the band.
  - In a trial, a finer near-axis step floor (2e-5 instead of 2e-4) cut the CPU's polar error
    tenfold, to 8.6e-4 M; 2e-6 made it worse again. The fix is open (§10).
  - Scale: one pixel is ~0.04 M (48 M over 1,200 pixels). Off-axis, the test is far finer than
    the display; it is a check of the ray solver, not of the drawn silhouette.
- **Equatorial light paths (`make claims`):** captured below the critical impact parameter
  and deflected by the Kerr angle, against a reference written independently of the theme
  (Bardeen's closed-form b_c, and its own quadrature of the orbit equation).
  - b_c matches to 2e-9 (prograde) and 4e-8 (retrograde), relative.
  - Deflections at 1.3–3 b_c match to ≤ 3.5e-5 rad.
  - Status: REFERENCE-VALIDATED.
- **ISCO:** Bardeen–Press–Teukolsky. r_isco = 3.745 M at a = 0.62, efficiency η = 1 − E_isco = 0.093.
- **Light-travel time:** each pixel's pattern phase includes the photon's coordinate travel time,
  relative to T_ref = r_obs + 2 ln(r_obs/2). Lensed images therefore lag the direct one.
- **Known artefact:** within ~3° of the spin axis, coordinate-singularity artefacts appear.
  The camera never goes there.

## 4. The disk: one relativistic solution

The disk is **computed**, not shaped by hand:

1. **Evolution equation:** the general-relativistic thin-disk equation (Balbus 2017;
   Mummery & Balbus 2019, MNRAS 489, 132), in ζ = r Σ W / U⁰:
   ∂ζ/∂t = (W/(U⁰)²) ∂/∂r [ (U⁰/U_φ′) ∂ζ/∂r ]
   - Stress closure: W = w (r/r₀)^{1/2}, independent of Σ (η = 0).
   - Boundary: zero stress at the ISCO.
   - Numerics: backward Euler with a Thomas solve.
2. **Initial ring and snapshot:** a ring of gas at 4 r_isco (width 0.8 r_isco), evolved until the
   radius where the mass flux reverses reaches 5 r_isco. The recipe (initial ring and snapshot
   criterion) scales with the ISCO, so it applies unchanged at any spin. The solution does not:
   the equation's Kerr coefficients depend on spin, so it is recomputed for each spin.
3. **Flux:** F = −(U⁰)² ζ Ω′ / (2r).
   - Near the ISCO it is steady inflow: F/F_Page-Thorne = 0.99 at 1.5 r_isco.
   - It falls below Page-Thorne outward: 0.89 at 9 M, 0.55 at 19 M, 0.28 at 28 M.
   - Mass budget closes to 0.998.
4. **Physical scaling:** the ISCO inflow is set to 0.36 Ṁ_Edd for 4e9 Msun, α = 0.1.
   - Convention: Ṁ_Edd = L_Edd / (η c²), with η = 1 − E_isco = 0.093 for this spin and
     L_Edd = 1.26e38 (M/Msun) erg s⁻¹.
   - The snapshot radiates 0.544 of a steady Page-Thorne disk at that inflow.
   - So L = 0.36 × 0.544 = 0.196 L_Edd, matching the measured 0.18. (With a fixed 10% efficiency
     convention the same inflow would read 0.182.)
5. **Local structure, at each radius:**
   - Σ comes from the flux and the stress.
   - Scale height comes from hydrostatic balance with gas + radiation pressure.
   - Midplane temperature comes from radiative diffusion, uniform heating: T_c⁴ = (3/8 τ_½ + 1) T_eff⁴.
   - Opacity: electron scattering κ_es = 0.34 plus Kramers κ_ff = 6.4e22 ρ T^−3.5 (cgs).
   - At the flux peak: H/r ≈ 0.05 (radiation-pressure supported), τ_es ≈ 350, Σ ≈ 2e3 g cm⁻².
6. **Emission:** a grey isothermal slab whose energy-conserving source temperature satisfies
   T_s⁴ = F / (σ (1 − 2E₃(τ_em))).
   - Emission depth τ_em = min(τ_a(1+τ_es), √(τ_a(τ_a+τ_es))), using full-slab depths.
   - Where the gas is thick to scattering (τ_ext ≳ 10) it is a scattering atmosphere: T_s = T_eff,
     full emission, and the spectrum is hardened only by the colour correction (§5).
   - The two treatments are blended in log τ_ext between 1 and 10. This avoids counting the
     scattering hardening twice.

Radial profile (from the test):

| r (M) | T_s (K) | τ_ext (vertical) |
|---|---|---|
| 5.6 | 49,900 | 663 |
| 18.7 | 25,400 | 586 |
| 37.4 | 11,400 | 97 |
| 56.2 | 5,600 | 13 |
| 74.9 | 4,500 | 1.6 |
| 93.6 | 4,900 | 0.17 |
| 112 | 4,600 | 0.018 |
| 150 | 4,300 | 1.6e-4 |

The disk ends at R_out = 48 r_isco = 180 M, where τ ≈ 1e-4, so the gas fades out with no edge.

## 5. Radiation

- **Redshift:** g = 1/(u^t (1 − Ω L)), with u^t and Ω for prograde circular Kerr orbits and
  L = −α sin i, the photon's angular momentum (E = 1).
  - This g is relative to an observer at infinity. A static camera at r = 1000 M would see every
    frequency × 1/√(1 − 2/1000) ≈ 1.001; that uniform 0.1% is not applied.
  - The observed spectrum is a blackbody at g × the colour temperature.
  - Colour and brightness come from Planck's law integrated against the CIE 1931 colour-matching
    functions.
  - Beaming is on.
- **Colour correction** (Done, Davis, Jin, Blaes & Ward 2012): f_col⁻⁴ B(f_col T).
  - f = 1 below 3e4 K, (T/3e4 K)^0.83 up to 1e5 K, and (72 keV/kT)^{1/9} above that.
  - The branches are continuous to 0.3%; f ≈ 1.5 at the 50,000 K peak.
- **Limb darkening:** I(μ) ∝ 1 + 2.06 μ (Chandrasekhar H-function, linear fit as in Laor 1991),
  normalised to an isotropic emitter's flux (tested to 1e-6).
  - μ is measured in the gas frame: μ = g |p_θ| / r.
  - It is weighted by 1 − e^{−τ_ext}, so it fades out where the gas thins.
- **Translucency:**
  - Emitted fraction 1 − e^{−τ_em/μ}; transmitted fraction e^{−τ_ext/μ} (slant depth).
  - Layering: per pixel, the brightest layer is the animated one; fainter translucent gas in front
    of it is composited as a static background, and its transmission dims the layer behind.
- **Exposure:** metered on the inner disk (99th-percentile luminance), with Reinhard tone mapping
  on luminance up to the display's EDR headroom.

## 6. Turbulence (statistics of MRI turbulence, not simulated MHD)

The targets are measured shearing-box and global MRI statistics (Guan et al. 2009; Beckwith,
Armitage & Simon 2011; Hirose et al. 2009):

- **Eddy shape:** the rendered, time-averaged 1/e correlation ellipse is ~1.8 H along the orbit
  by ~0.25 H radially (axis ratio ~7), trailing 12–14°.
  - H/r = 0.01 is a choice; this disk has ~0.05 at the peak.
  - Eddies are born leading ~31° and swung to trailing by the Kerr shear. Birth cells are
    2 × (0.294, 0.556) H.
  - The fit was made against the rendered field with an exact numpy port of the shader.
- **Spectrum:** two octaves with amplitudes 2^{−5j/6}, i.e. a k^{−11/3} per-mode spectrum.
  A third octave would be finer than a Retina pixel's footprint and is omitted.
- **Lifetimes:** P(r) · 2^{−2j/3}, on phase-locked bands L₀ 2ⁿ (L₀ = 4 M, 12 bands) blended
  across radius. Each band holds two staggered, independent generations with variance-preserving
  weights.
  - Every generation is advected at its own Kerr Ω(r).
  - The measured Lagrangian correlation time is 0.43–0.56 of an orbit.
- **Dissipation:** log-normal, ε = exp(σ G − σ² var/2) with σ = 0.2. Temperature follows it,
  T ∝ ε^{1/4}, so the ripple is ~5% in temperature.
- **Filtering:**
  - Variance-preserving interpolation between table cells, using fitted neighbour correlations.
  - Footprint filter (1 + (f/c)²)^{−1/4} per axis, fitted to box averaging (max error 0.045).

## 7. Hot spots

- Six plasma clumps on exact Kerr orbits, at radii 1.15–5.35 r_isco, each ~1.1 M across and
  living 90 M.
- Each spot shears as it ages: every radius keeps its own Ω(r).
- Emissivity × (1 + boost), so T rises as (1 + boost)^{1/4}.
- Count, size and brightness are choices; the motion is computed.

## 8. The sky is black

The camera sits inside the core of the cluster's giant central galaxy.

- **What the sky holds:**
  - Host starlight: μ_V ≈ 14.5–16 mag arcsec⁻² over the whole sky.
  - The nearest companion galaxies: ~8–10 mag.
  - Cluster members: ~11–14 mag. (Argon research, not individually verified.)
- **Why it is black:**
  - The Sun's surface brightness is −26.74 mag spread over π (959.6″)² = 2.89e6 arcsec²:
    −26.74 + 2.5 log₁₀(2.89e6) = −10.6 mag arcsec⁻².
  - At 550 nm a 50,000 K blackbody is ~133× brighter per area than the Sun's 5,772 K
    (−2.5 log₁₀ 133 = −5.3 mag), so the disk is ≈ −15.9 mag arcsec⁻².
  - Against the host's +14.5 to +16, the disk is ~30–32 magnitudes (~10¹²) brighter. At any
    exposure that shows the disk, the sky is black.
- Renders that show a sky expose it separately; this one does not.

## 9. How it was checked

Each test validates only its own claim: the Bardeen comparison checks the light paths, not the
disk's luminosity, the turbulence statistics or the radiative transfer, which have their own
tests or audits below.

- **Tests:** full-contour shadow edge vs Bardeen, CPU and GPU (§3); equatorial b_c and
  deflection vs an independent reference (`make claims`); photon orbits; geodesic invariants
  (null condition, Carter constant); Page-Thorne limits; blackbody colours; the redshift sign;
  the disk solution's mass budget, Page-Thorne limit, temperature and luminosity;
  colour-correction continuity and limb-darkening flux conservation.
- **Test ledger:** `make ledger` writes [`docs/opus_quasar_ledger.json`](opus_quasar_ledger.json),
  one record per checked claim, from the theme's tests, `make claims` and `make gpu-bench`.
  - Each record holds: the claim, the reference and its source, the test conditions, the
    measured quantity and its units, the bounds, pass/fail, and the command that produced it.
  - The tests assert through the same function that writes the record, so the ledger's
    tolerance is the test's.
  - Values with no bound (r_isco, η, the polar-band maximum, GPU/CPU pixel agreement) are
    reported, not asserted, and marked `"pass": null`.
  - Current ledger: 62 records; 54 asserted, of which 53 pass and 1 fails (the GPU's polar-band
    maximum, §3); 8 reported.
- **Reviews:** two independent physics reviews by Gemini 4 Argon, and two Claude Opus audits that
  wrote their own code (disk solver re-solved independently to 0.1%; turbulence measured on the
  tables). Every finding was re-derived before fixing; rejected findings are recorded in the
  project notes.
- **Literature:** a Claude Sonnet check of H1821+643's parameters (§1). Its luminosity finding
  (λ_Edd = 0.18) was verified against the paper before adoption.

## 10. Choices and known approximations

- **Camera:** inclination 88°, distance 1000 M, field of view, time-lapse.
- **Disk setup:** the ring start and snapshot (the disk is a spreading ring caught at one moment,
  not a steady disk). The flux is Page-Thorne-like only inside ~1.5 r_isco.
- **Stress closure:** the closure is Σ-independent. The α-pressure relation holds only at the
  flux peak, and further out it implies α ≫ 1.
- **Outer-disk opacity:** beyond ~70 M the gas is < 5000 K and neutral, so electron scattering and
  Kramers do not apply. True opacity (H⁻, molecules, dust) is not modelled: the fade is robust,
  but its exact radius and colour are not.
- **Fits, not computations:** the colour correction and the limb darkening are fits to
  disk-atmosphere models. Full calculations give a limb slope nearer 2.6, with up to 15% deviation.
- **Not modelled:** returning radiation (disk self-irradiation), finite disk thickness (the disk
  is drawn as a surface), gas inside the ISCO, polarisation, the corona and broad-line region
  (X-ray only or outside the view), the recoil.
- **Opacity mean:** the Rosseland-mean Kramers law is used where a Planck mean might suit
  emission better.
- **Near-axis step control:** rays that pass within a band ~0.002 M wide of the spin axis are
  integrated too coarsely (§3). The shadow edge there is off by up to 0.4 pixel on the GPU.
  This is not yet fixed.

## 11. Reviews so far

- **GPT (2026-10-16):** confirmed the spin, ISCO, efficiency, mass conversion and the
  inclination distinction. It corrected the Sun's surface brightness (−10.6, not −16 mag arcsec⁻²;
  the conclusion stands) and the spin-independence claim (the recipe scales, not the solution).
  It also asked for the Ṁ_Edd convention, the shadow test's scope and the observer lapse to be
  stated. All verified and fixed here. It then asked for a dense full-contour shadow sweep and a
  machine-readable test ledger. Both are done (§3, §9). The sweep found the near-axis error the
  11-point test had missed.

## 12. Questions for reviewers

1. Is a spreading-ring snapshot defensible for a quasar that has accreted for ~10⁸ yr, or should
   the disk be steady (Page-Thorne everywhere)? Does the drop below Page-Thorne past
   ~1.5 r_isco misrepresent H1821+643?
2. At λ ≈ 0.2 with H/r ≈ 0.05, is a thin disk still the right model, or are slim-disk
   corrections (advection) needed near the peak?
3. Is blending the slab model and the scattering atmosphere over τ_ext = 1–10 sound? Is there a
   standard treatment of the transition?
4. Is the colour correction of Done et al. 2012 appropriate for a 4e9 Msun disk at 50,000 K, and
   for the visible band (it was calibrated on soft-X-ray/UV continua)?
5. Are the MRI turbulence statistics (σ_ln ε = 0.2, ratio 7, tilt 12–14°, lifetime ~P/2) the
   right numbers to carry to the photosphere of a radiation-dominated disk?
6. Anything visible in optical light within ~100 M that we have left out?

Send corrections with a source (paper or derivation); each claim is re-derived before anything
changes.
