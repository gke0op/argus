# Opus_Orion_Nebula: data, model and fit

`themes/Opus_Orion_Nebula.metal` draws the centre of the Orion Nebula (M42, the Huygens
region, 0.68 x 0.57 pc) from measured data, through a model of the physics that is fitted
to those measurements. This file says which is which, how well the fit works, and what
stays uncertain. The full numbers of the latest bake are in the report that
`bake.py --report <dir>` writes.

## Rebuild

```bash
python3 -I tools/orion_bake/bake.py --cache ~/orion-cache --report ~/orion-cache/report
```

It needs numpy and scipy. It downloads about 230 MB of MUSE maps, then streams about 2.4 GB
of the Edenhofer dust map. It keeps 64 sightlines from that stream and caches them, so the
stream happens once. It rewrites `themes/Opus_Orion_Nebula.bin` and the `BEGIN BAKED` block
of the theme.

```bash
python3 -I tools/orion_bake/verify_earth_view.py <frame.png> --diff diff.png
```

This checks a harness frame of the theme with the orbit frozen. Set `ORBIT_YAW` and
`ORBIT_PITCH` to 0 in a copy, next to a copy of the `.bin`. The script rebuilds the same view
in numpy from the shipped data and compares the two.

## Measured, fitted, assumed

| | What | Source |
|---|---|---|
| **Measured** | Dereddened line maps: Hα (= Hβ x 2.89), [O III] 5007, [N II] 6584, [S II] 6731, [O I] 6300 | VLT/MUSE, Weilbacher et al. 2015, data doi:10.17876/data/2023_3 (CC0) |
| Measured | Reddening c(Hβ) | same |
| Measured (fit only) | [S II] electron density; Hα, [N II], [S II] velocities | same |
| Measured | Positions and V magnitudes of 12 bright stars | SIMBAD |
| Measured (reconstructed) | Dust in front of Orion, out to 360 pc | Edenhofer et al. 2024 (CC BY 4.0) |
| **Fitted** | The ionisation front's 3D shape (15 x 13 B-spline control points) | photoionisation balance vs the Hα emission measure |
| Fitted | Flow scale R0 per texel (one clumping factor φ) | emission measure, [S II] density, curvature of the fitted front |
| Fitted | Where the ions shine ([N II], [S II], [O I] on the front; Hα, [O III] in the flow) | the measured velocity offsets |
| Fitted | Foreground ISM vs Veil split of c(Hβ) | Edenhofer map vs MUSE c(Hβ) |
| **Assumed** | Distance 400 pc; Te = 9000 K; c_s = 11 km/s; Q(θ¹ Ori C) = 1.7e49 s⁻¹, Q(θ² Ori A) = 1e48 s⁻¹ at θ¹ C's depth | literature (see the theme header) |
| Assumed | An isothermal photoevaporation flow, sonic at the front (Henney et al. 2005) | |
| Assumed | The Veil as a thin screen 1 pc in front of θ¹ Ori C | O'Dell et al. 2009 (published range 0.4–3 pc) |
| Assumed | No dust inside the ionised gas, and no scattered light | |
| Assumed (statistical) | The fainter cluster stars | ONC structure (Da Rio et al. 2014), Kroupa IMF, rough 1 Myr luminosities |
| **Chosen** | Orbit (±4.3° yaw, ±2.6° pitch, 8 min), exposure, asinh stretch, chroma compression, star image | display |

## The model

1. **The front.** Every patch of ionisation front absorbs the ionising photons that reach it
   at its angle to the star. In steady state it balances them with recombinations in the gas
   in front of it: Φ·n̂ = α_B ∫n² dh. That gas is seen through at the angle of the line of
   sight, so EM_obs = EM_⊥ / n_z. The front is a smooth surface z(x, y), fitted by least
   squares to the measured log emission measure (smoothed 8″) from θ¹ Ori C and θ² Ori A,
   with a curvature penalty. A per-pixel inversion is ill-posed: brightness alone can't
   separate depth from tilt, and it runs away into vertical walls. A smooth global surface
   fixes that (the approach of Wen & O'Dell 1995). Small-scale structure stays in the line
   maps.
2. **The flow.** The ionised gas leaves the front as an isothermal flow, divergent and sonic
   at the front: n M R² = const, M²/2 + ln n = const (Henney, Arthur & García-Díaz 2005).
   Its n² profile has a fixed shape in h/R0, with ∫(n/n₀)² dh = g·R0, g = 0.121. R0 per texel
   is EM_⊥/(g n₀²). n₀ is the [S II] density times one clumping factor, fitted so that R0
   matches the fitted front's own mean curvature radius.
3. **The ions.** The flow predicts the emission-weighted speeds. If [N II] came from the
   front itself, Hα would lead it by (17.7 − 11.0) km/s × n_z. The bake compares that with
   the measured [N II] − Hα centroid offset; see the numbers below.
4. **Extinction.** Total c(Hβ) is measured. What the Edenhofer map puts in front of 360 pc is
   a distant screen, and the rest is the Veil.
5. **Rendering.** Each pixel finds where its ray meets the front. It integrates the flow
   emission exactly per segment (tabulated CDF, with the remainder added at the last step),
   adds the low-ionisation sheet at its viewing angle, applies the Veil and ISM extinction
   line by line, and sums CIE XYZ.

## Fit quality (bake of 2026-10-16)

- **Earth view reproduces the data.** A GPU frame with the orbit frozen, against an
  independent numpy rebuild from the shipped file: median 0.26 / 255 display levels, 99th
  percentile 1.2, over 94% of pixels (stars masked).
- **Encoding.** The 8-bit log encoding errs by 0.002–0.003 dex rms per line (< 1%).
- **Destriping.** The removed MUSE slicer pattern is 1.5–3.7% rms (vertical and horizontal,
  per line). The removed pattern holds no nebular structure.
- **Front fit.** Residual in log EM (8″ scales): 0.041 dex rms, 5–95% within ±0.066 dex.
  Maps: `front_resid.png`, `front_depth.png`.
  - Depth below θ¹ Ori C: 0.165 pc. The published value is ~0.2 pc at 440 pc, i.e. 0.18 pc
    at 400 pc. This is an independent check: the fit never saw that number.
  - Front depth range 0.12–0.35 pc. Median tilt 23° from the line of sight; it curves up
    toward us, a concave bowl around the Trapezium. No part faces away from the stars.
- **Velocity test.** [N II] − Hα predicted +6.31 km/s, measured +6.04 km/s (brightest 40%).
  Per texel: median residual −0.21 km/s, rms 2.2 km/s (`vel_resid_nii_ha.png`).
  - An N⁺ zone thicker than 0.011 R0 would miss by more than 1 km/s.
  - [S II] is a further +1.1 km/s toward the cloud's velocity. It shines partly inside the
    accelerating front, below the sonic point. The model draws it on the front sheet; it
    has no layer of its own.
- **Bright Bar test (geometry).** The Bar is a nearly edge-on stretch of front, so across it
  the ions spread out on the sky by height. The emission peaks fall in order going toward
  the Trapezium: [O I] −26 mpc, [N II] −9, [S II] 0, Hβ +28, [O III] +29. That is the
  model's layering. The whole span is 55 mpc; drawing the low ions as one sheet misplaces
  them by at most 4 mpc (3.6 texels) at the widest yaw. Toward the star, Hα doesn't drop to
  half within 46 mpc of its peak, so R0 ≳ 0.13 pc, consistent with the fit (0.29–1.5 pc).
- **Dust.** Edenhofer's map toward θ¹ Ori C puts almost nothing in front of 360 pc
  (A_V ≈ 0.08 mag, uniform over all 64 sightlines). So 93% of the median measured
  reddening is the Veil.
  - The same sightline shows the Orion cloud as a dust wall at 427 pc (10–90% between 417
    and 436 pc): the molecular cloud whose surface is our front, just beyond the stars'
    388–414 pc.
  - Veil encoding error: < 0.7% in Hβ transmission. No texel needs clipping.
- **Clumping.** φ = 0.22: the flow needs a front density 2.1 times the [S II] density. An
  independent check comes from [Cl III], which traces the denser gas nearer the front, in
  the same data. Over the bright half of the field it reads 1.64 times the [S II] density
  (16–84%: 1.33–2.04), i.e. φ = 0.37. So the two estimates of the layer thickness agree
  within a factor of 1.7. R0 median 0.9 pc, so half of Hα lies within
  0.12 pc of the front. Classic estimates of the layer are 0.07–0.2 pc.

## What stays degenerate or uncertain

- **Layer thickness (R0).** This is the least certain fitted quantity. The front's curvature
  gives R0 ≈ 0.9 pc; the [Cl III] density gives 1.6 times that. Older 2e17 cm estimates of
  the layer point the other way, to about half. So R0 is known to within roughly a factor
  of 2. What that changes on screen: at the orbit's widest yaw, 0.6× or 1.7× R0 moves the
  median pixel by 3/255 and the 99th percentile by 11–12/255. From Earth it changes nothing. It changes only the off-Earth views: from Earth the
  image is the data either way.
- **Absolute depth.** The depth scales as √Q (Q itself is ±10%) and with the assumed
  distance. The dust absorbing ionising photons inside the gas (Henney et al. 2005:
  f_d ≈ 0.5) is not modelled; including it would pull the front ~30% closer.
- **The Dark Bay.** The front comes out deepest there, and the fit residual is largest
  (±0.07 dex). Weilbacher et al. note that their reddening correction is imperfect in the
  Dark Bay, so leftover dimming there reads as depth.
- **Front tilt below 8″.** It is smoothed. A feature such as the Bright Bar is a tilted
  escarpment in the real nebula; here it is in the line maps but only partly in the
  geometry.
- **θ² Ori A's depth.** Unknown; it affects only the south-east corner.
- **The Veil's distance.** Published values run from 0.4 to 3 pc. It sets how far the
  extinction pattern slides as the view orbits.
- **[O III] layering.** There is no [O III] velocity map, so it is assumed to fill the flow
  like Hα.
- **Things not modelled.** The Orion-S cloud inside the ionised gas (O'Dell et al. 2009),
  shocks and Herbig-Haro flows, proplyds as 3D objects (they are in the line maps), dust
  scattering, and M43 (outside the field).
