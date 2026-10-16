# Theme craft: from "harness PASS" to a theme worth keeping

Shared by [`argus-metal-theme`](argus-metal-theme/SKILL.md) and [`argus-theme`](argus-theme/SKILL.md).
Read it before you write code. The skills tell you how to make a theme *run*; this file
covers how to make one *good*.

## The bar

The harness is the floor. In October 2026 a batch of six agent-made themes all passed it,
and the owner's verdict was "at best sub par". The themes that ship (Night Tide, Orion
Nebula, Cygnus A, Ebru Studio) and the best of the earlier ones have these things in common:

1. **A specific subject, not a genre.** Not "deep sea" but one named lagoon at 2-15 m.
   Not "glowing waves" but a California red tide on a moonless night. Not "a black hole" but
   Cygnus A's mass and Eddington ratio. Being specific is what forces the research.
2. **Research into the look, not only the physics.** What it looks like to the eye, and in
   photos, and where those two differ. Night Tide: "to the eye the glow is a soft grey-blue …
   long-exposure photos make it neon. This aims between the two."
3. **Every researched fact becomes a visible decision.** "Cells flash only above a shear
   threshold that breaking waves reach" turns into "the swells are dark and only breaking water
   glows". A fact that changes no pixel is decoration in the header.
4. **Restraint and a value plan.** One light source, a chosen darkest thing ("sand is the
   darkest thing in view"), one accent colour, and black where nothing is happening.
5. **Motion in human time, stable for hours.** Rates are designed in seconds and minutes, there
   is no shimmer, and nothing freezes, explodes or loops visibly after an hour.
6. **An honest header.** It separates what is measured or computed from what was chosen and
   what isn't modelled, and it names nothing that isn't on screen.
7. **Many rounds against reality.** Night Tide took three more commits after its first version, shaped by the owner's corrections;
   Orion had two adversarial audits. The first version that passed was never the one that shipped.

## The workflow

**1. Brief (one paragraph).** State the specific subject, the moment (time of day, weather,
season, phase), the viewpoint, and the one thing the viewer should feel or notice. If you were
given a genre, pick a real instance and say why you picked it.

**2. Research, before any code.** Keep two lists in a notes file:
- *How it looks:* photos, footage, eyewitness descriptions, field guides. Note colour, value,
  scale, texture, how the light behaves, what is surprisingly dark or bright, and how the eye
  differs from the camera.
- *Why it looks like that:* the mechanism, with real scales, rates, colours and units.

Tag each fact with how well you know it: `[cited]` (page read),
`[snippet]` (search result only), `[data]` (a dataset). Write down what you will leave out
because you couldn't source it. Physics citations are not a visual reference: a paper on
thin-film drainage doesn't tell you what a rainy window looks like.

**3. Look targets.** Turn the research into 5-10 statements that you can check against a
render. Each one should be falsifiable from the PNG:
- "The sand is the darkest thing in the frame."
- "The fish nearest the camera are the most saturated; beyond 8 m everything shifts to the water's blue-green."
- "Only breaking or running water glows; open swells stay dark."
- "Every pool of liquid metal shows the ceiling lights sliding across it."

**4. Art direction, before any code.** Write down the camera and framing; the value plan
(darkest, brightest, roughly what share of the screen is dark); a palette taken from the
subject (measured spectra, photographs), not from `argus_palette` defaults; the focal element;
and a motion plan in seconds per event, including what changes over minutes and over an hour.
Remember this is a desktop: windows cover most of it most of the time, the menu bar sits on the
top edge and the Dock on the bottom, and it runs for days.

**5. Build the smallest version that shows the main look**, run the harness, and look at the
result. If the core idea doesn't read in round one, more features won't save it. Change the
idea now. (One factory author scrapped a theme only after building all of it.)

**6. The render loop.** Run `tools/theme_sheet.sh themes/<Name>.metal` (Metal) or the harness
at several `FRAMES` (Zig). Then:
- open every image, including the 1:1 crop (a downscaled full frame hides aliasing and banding);
- critique it in writing against your look targets and the checklist below, citing items
  ("A2: all midtones, no darks"; "A5: drops read as grey bubbles, not water");
- fix the worst item, re-render, and repeat. Expect 10-20 rounds. Keep a *tried and dropped*
  list ("a smooth canopy read as moss; 10 cm tufts were blocky").

Critique the way the owner does: short, concrete, against reality. The owner's real notes
include "water soaks in", "sand is the darkest thing at night", "the falling motes read as
sperm" and "zoom out". To get this kind of critique yourself, cover the header, look at the
picture, and say what it actually shows.

**7. Check the claims.** Every number in the header is either cited or checked (a unit test,
a claim ledger (`sdk.ledger`, as in `themes/Cygnus_A.zig`), a verify script like
`tools/orion_bake/verify_earth_view.py`, or a measurement from a render). Every noun in the
header ("plumes", "caustics", "bokeh") must be visible in the sheet. A defect you know about
gets fixed, or the claim gets dropped. Disclosing it isn't enough.

**8. Show the owner early.** Send the sheet, three lines on your choices, and your open
questions, at round 3 rather than round 20. For subjective parameters, give a sweep instead of
a single guess: one black-hole theme's inclination was picked by the owner from a 1° sweep
from 80° to 90°.

**9. Independent review.** Give a fresh agent (ideally another model family) the header, the
sheet and your references, and ask it to refute the claims and name what reads wrong. Orion's
audits found that 9 of its 12 real stars were silently dropped by a `//` in generated code,
and that stars were dimmed twice. All of it passed the harness.

**10. Write the header** (template below) **and a field notes entry.**

## The critique checklist

Use these IDs in written critiques.

| ID | Criterion | How to check |
|---|---|---|
| A1 | **Reads as the subject** | Cover the header and look at the sheet: would a stranger name the subject? Does each material read (water wet, metal mirroring something, sand matte)? |
| A2 | **Value structure** | Squint or blur: is there a clear pattern of big shapes, a chosen darkest and brightest? Not all midtones, not crushed to black, not blown out. |
| A3 | **Focal point and composition** | Where does the eye land? Does any uncovered quarter of the screen still read? Nothing important under the menu bar or Dock; no frame or ornament competing with the desktop. |
| A4 | **Colour** | Colours come from the subject (measured or photographed), with few hues and one accent. Saturation is earned, not a default cosine rainbow. |
| A5 | **Light and material** | Light comes from somewhere and stays consistent. A mirror needs something to reflect; a lens needs something bright behind it. |
| A6 | **Depth and scale** | Real units, atmospheric perspective, detail that falls off with distance, believable size relations. |
| A7 | **Motion** | Rates are designed in human time. Something changes on the scale of seconds, minutes and the hour. No strobing or shimmer (measure flicker), no visible loop, and still alive at 90 s and at an hour. |
| A8 | **1:1 detail** | Look at the crop: no aliasing, banding, hard clipping edges, grid or seam artefacts. |
| A9 | **Restraint** | Every element earns its place; remove what doesn't serve the subject. |
| A10 | **Honesty** | Header and screen agree, both ways. |

## Failure modes from the factory batch (2026-10-16)

The batch is private and unreleased, so it is described here, not named. Each theme was
rendered at frame 900 with the harness seed, and each one passed every gate.

| Theme | What the header promises | What renders | Failure modes |
|---|---|---|---|
| a stateless interference pattern | sharp 5-fold peaks, iridescent | near-black flat triangular facets with vertical seams; the scale shows ~2 waves per screen | genre, not subject; header ≠ screen; mud values; a ShaderToy staple with a cosine palette; its field note reported only harness numbers |
| a deep-sea scene | glowing creatures with tentacles, caustics, marine snow | four soft grey-green discs, one line each, on black | no reference; empty composition; scrapped late |
| rain on a window at night | an out-of-focus city through droplet lenses | a hard-edged rectangle skyline; bokeh discs cut in half at the skyline; drops read as grey bubbles with dark holes | material doesn't read (A1, A5); no photo reference (a real one shows a fully blurred city, each drop holding it small and inverted) |
| a convection cell | plumes that rise, mushroom and shed | soft vertical brown and navy bands, murky midtones | rigour spent where it's invisible (a ledger for the critical Rayleigh number while the picture is mud); a box of 0.57 critical wavelengths forces one roll, disclosed but not fixed |
| a marbling bath of liquid metal | the metal as a mirror, in an engraved vessel | flat grey cut-out shapes; a bevelled frame with lettering takes about a third of the screen | concept over look; the mirror has nothing to reflect; ornament fights the desktop (A3, A5, A9). Ebru Studio, below, is what it became |
| a thin film in a dark room | interference colours lit by one lamp | computed spectral colours and real drainage plumes, the nearest to the bar | no lamp, room or edge, so it reads as a full-screen colour field; evenly busy stripes with no place for the eye to rest |

The patterns, and the step that prevents each one:

- **Genre, not subject:** step 1.
- **No visual reference** (physics citations standing in for one): step 2.
- **Header and screen disagree:** steps 3 and 7.
- **Rigour where it changes no pixel:** check what is *visible* first: plume shape, glow placement, colour.
- **Mud values, no focal point:** step 4, A2, A3.
- **Materials that don't read:** A1, A5.
- **Judged from one frame and one seed:** step 6 and the sheet.
- **Rates tuned in simulation units:** see "Design rates in human time" in the Metal skill.
- **Stopping at "harness PASS":** the definition of done in each SKILL.md.

## Worked examples

From the shipped themes:

- **Night Tide** (`themes/Night_Tide.metal`; commits e1ccf44 → 20d9fae). Each research fact
  ends in a visible rule: the shear threshold makes swells dark; brief ~475 nm flashes make
  the glow grainy and blue; recovery time means water that just lit glows less. Owner
  corrections reshaped it: sand matte and near-black, the darkest thing in view; swash that
  stops, parts and soaks in; mostly small waves in sets, about one in twelve big. When the
  waves hit the map's end, the map became periodic. The optimisation pass (4.9 → 2.9 ms) was
  proven to leave the image unchanged by diffing four moments (mean 0.1-0.16/255).
- **Orion Nebula** (`themes/Orion_Nebula.metal`). The header is split into MEASURED / FITTED
  / ASSUMED. The Earth view is verified against the MUSE data (median 0.25/255 off), and two
  adversarial audits caught bugs the harness never could. The true colour is a surprising
  teal ([O III]). It was kept because it is measured, and a false-colour mode is offered with
  a label.
- **Cygnus A** (`themes/Cygnus_A.zig`). The header has "what is computed, not chosen" and
  "what is chosen (stated honestly)". The chosen list includes the unmeasured spin, the
  time-lapse (one inner orbit in ~3 s on screen against ~4 days in reality), and turbulence as
  noise carrying measured MRI statistics rather than simulated MHD. It was audited by two
  model families.
- **Ebru Studio** (`themes/Ebru_Studio.metal`). It grew out of the factory marbling bath above,
  and the fixes are the lesson. The mirror got something to mirror: a glass ceiling with a 3x7
  grid of studio lights, reflected with footprint filtering so the lights never alias into
  grain. The ink became a glossy dielectric with Fresnel reflection. The engraved vessel became
  a slim brushed-aluminium frame. The physics (Stokes flow, exact area-adding drops) carried over
  unchanged; what changed was the look.

Lessons from earlier themes that are no longer in the tree:

- **A sourced site brief.** A Great Barrier Reef lagoon theme tagged every fact `[cited]` or
  `[snippet]`, used real scale (1 unit = 1 m), put the fog at the measured 11-16 m visibility,
  and listed what it left out "because not sourced". It fixed shimmer by measurement: seabed
  pixels jumping >40 levels per frame went 1.60% → 0.70% → 0.64%. The diagnosis was "the
  shimmer was contrast, not sampling".
- **Restraint.** A reservoir-computing theme let one quantity (a neuron's "life") drive size,
  glow and the white core together, with everything else black. It was built for days: RLS
  without forgetting, because forgetting overflows after minutes.
- **A deliberate mapping.** A chimera-state theme mapped hue to each oscillator's phase and
  brightness to its agreement with its neighbourhood. One parameter breathed over seven
  minutes, so the field never settled.

## The honest header

```
// TITLE // themes/Name.metal
// Author (model), date.
//
// What you see: 3-6 plain lines on the scene, the moment, and what moves.
//
// Sources ([cited] page read, [snippet] search result only, [data] dataset):
//   - fact [tag] -> how it shows here
// COMPUTED / MEASURED: what comes out of the model or data, not tuned by eye.
// CHOSEN: everything picked by taste: camera, palette not from data, the time-lapse
//   factor (screen seconds per real second), any constant tuned to look right.
// NOT MODELLED: what a knowledgeable viewer would expect and won't find, and why.
// CHECKED: what verifies the claims (tests, ledger, verify script, audit), and
//   what is not checked.
// How it works: kernels, state layout, data.
// Cost: back-to-back and paced ms, on a quiet machine (say so if it wasn't).
// @argus directives
```

If a claim can't go under COMPUTED or CHECKED, it goes under CHOSEN or it comes out.
