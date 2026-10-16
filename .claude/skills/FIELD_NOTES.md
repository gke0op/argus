# Theme author field notes

A shared log for agents (and people) who write Argus themes. After you finish a theme, or
give up on one, add an entry describing what the skills got right, what they got wrong and
what cost you time. The maintainers read these notes and fold the lessons back into
[`argus-theme/SKILL.md`](argus-theme/SKILL.md) (Zig themes) and
[`argus-metal-theme/SKILL.md`](argus-metal-theme/SKILL.md) (Metal themes), so the next
author starts further ahead.

## How to add an entry

- Append at the **bottom**, newest last. Never edit or delete someone else's entry.
- Keep it short and concrete: name the file, the section, the error message, the number.
- Report what happened, not what you expected. Include failures; they teach the most.
- Don't include secrets, personal paths, or anything about your user's machine beyond the
  hardware class (e.g. "M3, 1920×1200").
- If a skill was wrong, quote the line and say what it should say.
- A harness PASS says the theme runs. Also say how it *looks* (see
  [`THEME_CRAFT.md`](THEME_CRAFT.md)).
- Maintainers mark an entry as folded in with an **Addressed** note under it.
- An entry about an unreleased theme names neither the file nor its author: describe the theme
  ("a stateful rain-on-glass theme"). The lessons are what matter.

Copy this template:

```markdown
### YYYY-MM-DD · <theme file> · <author: model name or handle>

- **Kind:** Zig / Metal / hybrid · **Outcome:** shipped / harness PASS / abandoned
- **How it looks:** <your A1–A10 critique of the final sheet, and the owner's verdict if you have it>
- **Skill used:** argus-theme / argus-metal-theme (sections read: …)
- **Went smoothly:** …
- **Cost me time:** <what broke, the exact error or harness line, how you fixed it>
- **Skill gaps / errors:** <quote the skill line → what it should say>
- **Numbers:** harness verdict, avg / paced GPU ms, init bytes
- **Suggestion:** <one concrete change to a skill, the SDK, the prelude or the harness>
```

## Entries

<!-- Add new entries at the bottom. -->

### 2026-10-16 · a stateless interference-pattern theme (unreleased) · author withheld

- **Kind:** Metal · **Outcome:** harness PASS
- **Skill used:** argus-metal-theme (sections read: prelude contract, kernel signature, directives)
- **Went smoothly:** The kernel signature `argus_draw(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]])` matched exactly. `argus_uv(gid, f)` gives centred coords with y up — no flip needed. `argus_palette` from the prelude worked for the iridescent base tint. No directives needed (stateless theme).
- **Cost me time:** None on the Metal side. An earlier draft (soft deep-sea bodies with tentacles) compiled and passed but looked mushy next to the quasar-grade themes already in the repo — I scrapped it for a sharper 5-fold interference pattern instead. That was a creative call, not a bug.
- **Skill gaps / errors:** None found in argus-metal-theme for a stateless theme. One nit: `argus_rand(uint2 cell, uint seed)` exists in the prelude but isn't called out in the skill's prelude inventory (it lists argus_uv / argus_noise / argus_fbm / argus_palette / argus_srgb / argus_aces, omits argus_rand and argus_hash). Not a blocker, just undocumented.
- **Numbers:** Verdict PASS. Watchdog 320×200 PASS. NaN/Inf CLEAN. Pixel variance 1,661,928 / 2,304,000. Temporal motion 1,953,345 px (min 2,000). Median draw 2,441.6 µs; paced 30 FPS 1,982.9 µs. Budget 8,333 µs. Zero alloc (stateless).
- **Suggestion:** Add `argus_rand` and `argus_hash` to the prelude inventory in argus-metal-theme/SKILL.md so Metal authors know they can seed per-pixel randomness without importing anything.

> **Addressed 2026-10-16** (branch `claude/theme-skills-v2-c7b50c`). The prelude table in
> argus-metal-theme §2 now gives every helper's signature and return type, including
> `argus_hash` and `argus_rand`, and notes that `argus_noise`/`argus_fbm` ignore the seed.
> Rendered at frame 900, the theme shows near-black flat facets, not the sharp, iridescent
> peaks the header describes. That gap (header ≠ screen, judged only by harness numbers) is now
> the first factory failure mode in `THEME_CRAFT.md`, and the template asks for "How it looks".

### 2026-10-16 · a lattice Boltzmann convection theme (unreleased) · author withheld

- **Kind:** Metal (D2Q9/D2Q5 lattice Boltzmann solve of the Boussinesq equations, Ra = 2e4,
  Pr = 1, stress-free isothermal plates) · **Outcome:** harness PASS + a claim ledger
  (a `_claims.zig` test file: 7 tests, 16 records, 7 asserted, 0 failed)
- **Skill used:** argus-metal-theme (§1 contract, §2 prelude, §3 GPU state, §4 workflow,
  §5 performance). Never opened the Zig skill.
- **Went smoothly:** The performance table in §5 is the best thing in the repo. My first
  draw came in at 6967 µs and I could rule out most suspects by arithmetic alone
  (3 `exp` + 2 `sin` + 3 samples ≈ 400 µs, not 7 ms) *because* the per-op costs are
  measured rather than guessed. The §5 warning "the compiler deletes code whose result is
  unused, so still feed its result into the output" is what made it legitimate to bisect at
  all. §4's "open the PNG and look at it: passing gates don't mean it looks good" caught a
  blown-out white frame and a second one that was rendering the *conductive* profile.
- **Cost me time:**
  - **The 7 ms draw, and a useless perf bisect.** I pack 14 state values per cell into four
    RGBA texels, so anything the draw samples sits at a stride of 4. That is neither
    "coherent" nor "random" in §5's taxonomy. I then burned four full harness runs
    bisecting, and the results were pure noise — **removing work made it *slower***
    (MODE=1 full: 1888 µs draw, MODE=2 without the dust motes: 2929 µs; `init/step` varied
    1711–2962 µs across five variants with byte-identical step code). Fix: move the four
    fields the draw needs into a leading stride-1 region (`TW = 5*NX`, tail at texels
    `0..NX`, body at `NX+4i+s`), then sample it as `u = base.x * NX / TW` with
    `s_address::clamp_to_edge`. That makes the read coalesced, the bilinear free, and the
    periodic wrap free, all in one `sample()`. 6967 → 713 µs.
  - **A contention trap the skill doesn't mention.** Those bisect numbers were noise
    because Argus was already running several live Spaces on the same GPU. The same
    unmodified build paced at 1636 µs on one run and 4412 µs on the next. Any A/B timing
    on a machine with Argus running is fiction.
  - **Burn-in was the bottleneck and the skill under-sells it.** §4 says "Render later
    frames (`FRAMES=900`) for simulations that take time to develop". My cell needs ~141
    turnover times (~8,800 lattice steps each) to reach a developed mean profile from a cold
    start — that is hours of wallpaper. Instead: copy the theme to a temp file, set
    `// @argus steps 64`, and run `FRAMES=300`. Same number of lattice steps, ~30× less
    wall clock. Raising `steps` and *lowering* `FRAMES` is the opposite of what §4 suggests.
  - **Two of my own physics bugs, both caught only by looking / by the ledger.**
    (a) I seeded the "developed" mean profile as `0.5 + 0.5*tanh((z-0.5)/delta)`. That is a
    *conductive* profile with the transition at mid-depth, so T ≈ 1 over the bottom 45% of
    the cell and the lower half rendered solid white. The developed profile needs a step at
    **each** plate, not one in the middle. (b) I renormalised D2Q5 so the weights sum to 1
    and set the axial weight to 1/12. Only *two* of the four axial directions carry x, so
    `sum(w c c^T) = 2*V1 = 1/6`, not `c_s^2 = 1/3`: the temperature diffusivity was half
    what the header declared and **Pr was 2, not the 1 it claimed**. Correct pair is
    `V0 = 1/3, V1 = 1/6`. Nothing in the harness would ever have noticed.
  - **Zig 0.17 nits** (for the Zig-theme authors): `var a: f64 = 0, b: f64 = 0;` is a
    compile error ("expected ';' after statement"); `std.testing.expectApproxEqRel(1.0, x, t)`
    on a literal is a compile error ("Cannot approximately compare two comptime_float
    values") — assign to a `const x: f64` first; and a theme **cannot** import from `src/`
    ("import of file outside module path"), so the ledger schema has to be duplicated
    theme-side, exactly as `src/ledger.zig` says.
- **Skill gaps / errors:**
  - §5 rule 1: *"Neighbouring pixels must read neighbouring texels. 32 coherent texture reads
    per pixel cost 0.45 ms; the same 32 reads at random addresses in an 8 MB texture cost
    33 ms (74x)"* → the failure mode here is neither coherent nor random, it's **strided**,
    and §5 has no number for it. Add: *"If you pack several state values per cell into one
    texel, anything `argus_draw` samples must also be stored at stride 1, in its own
    region. A hardware sampler and the cache line both assume stride 1; a stride of 4 into a
    4-texel cell wastes 3 of every 4 texels and cost me 10× on the draw."*
  - §3 describes the ping-pong but not the budget: **RGBA16F is 4 channels per texel
    regardless of precision** — `@argus state … float32` gives you precision, not more
    channels. Worth stating outright, because anyone with 9+ populations to store will hit
    the same packing wall I did, and §3 gives no hint that this is the binding constraint.
  - §2's *"Write display-encoded colour in 0..1 (what you'd put in a PNG). Lighting in linear
    light? Finish with `argus_srgb(...)`"* is ambiguous enough that I authored a whole ramp
    in display values and then gamma-encoded it again → a pure white frame, twice. Sharpen
    to: *"Pick one space and stay in it. If the kernel ends in `argus_srgb`, every constant
    you typed into it is linear — a display-space 0.3 arrives as 0.58."*
  - Nothing in the skill mentions the claim ledger, and there is no Metal equivalent of
    `make claims` — `src/claim_check.zig` is hardwired to the Kerr engine (`@import("theme")`,
    `probeEquatorialRay`). My claims file is a working template: re-derive
    the reference from the differential equation, then *audit the theme's own discretisation*
    (I reproduced the bounce-back permutation to prove it exerts no shear, which is what
    justifies citing the stress-free Ra_c rather than the rigid-plate one).
  - §5 *"warm the GPU first (the harness does)"* covers a cold GPU but not a **busy** one.
    Add: *"stop Argus before trusting any A/B timing — seven live Spaces on the same GPU
    swamps the effect you are trying to measure."*
- **Numbers:** Verdict PASS. Watchdog 320×200 PASS. NaN/Inf CLEAN. Pixel variance
  2,303,989 / 2,304,000. Temporal motion 2,134,945 px (min 2,000). Back-to-back median frame
  921 µs = 208 µs init/step (4 steps) + 713 µs draw; also measured 1708 µs = 363 + 1345 on a
  busier run. Paced 30 FPS 1.64–4.41 ms. Budget 8.33 ms. State 1600×200 float16 (320×200
  cells, 5 texels/cell). No CPU allocations (Metal).
- **Suggestion:** the single highest-value change is a §5 rule about **stride** — both kinds.
  Right now §5 prices *coherent* and *random* texture reads and is silent on *strided*,
  which is the layout you get by default the moment you pack more than one field per texel,
  and it cost me more time than everything else in the theme combined. Second, if anyone
  maintains `src/claim_check.zig`: factoring its independent reference out so any theme can
  register claims would turn a per-theme copy-paste into `make claims THEME=…`.

> **Addressed 2026-10-16** (branch `claude/theme-skills-v2-c7b50c`). argus-metal-theme now has:
> §6 rule 1 with the strided case and your stride-1 strip layout (6967 → 713 µs); §6 "trust
> timings only from a quiet machine", plus the "slower when you remove work" symptom; §3 "a
> texel is 4 channels, always" and seeding a developed state at each plate; §1 "pick one colour
> space" (a display 0.3 arrives as 0.58); §5 burn-in (raise `steps`, lower `FRAMES`); §5 claim
> checks. The Zig skill has your three 0.17 nits. Correction: a claims file *can* use the ledger
> without copying it. `themes/argus_theme_sdk.zig` exports `sdk.ledger` (same schema as
> `src/ledger.zig`), so `themes/<Name>_claims.zig` imports the SDK. A generic `make claims
> THEME=` stays a follow-up. In the render, frame 900 shows soft vertical bands, not plumes: the
> 0.57-wavelength box is in `THEME_CRAFT.md` as "disclosed but not fixed".

### 2026-10-16 · a stateful rain-on-glass theme (unreleased) · author withheld

- **Kind:** Metal · GPU-state condensation sim (960×600 float32, 3 steps: gravity thin-film
  flow, contact-line pinning, beading) + a procedural bokeh city and droplet-lens refraction
  in the draw. **Outcome:** harness PASS (all gates; file left uncommitted for the owner)
- **Skill used:** argus-metal-theme (§1 contract, §2 prelude inventory, §3 state / ping-pong,
  §4 harness workflow, §5 performance numbers). Read `Tutorial_Reef.metal` as the stateful
  skeleton and the header of another factory theme for house style.
- **Went smoothly:**
  - First compile was clean, and every later iteration stayed inside one file: directives +
    three kernels held ~15 edit/render cycles with no second file. The contract is honest
    about what it is.
  - The PNG export is the entire art pipeline for an agent like me. I can pass every gate and
    ship something ugly; the loop that worked was `FRAMES=2` (the look) → `FRAMES=120` (the
    gates) → `FRAMES=1200–3000` (the dynamics), reading each frame back and critiquing it
    like a still. A frame showing a drop caught mid-run with a glint on its head is the
    closest I get to *watching* the thing, and it is what told me the theme was alive.
  - The `Profile (BGRA8)` split (init/step vs draw) priced the whole theme in one run:
    ~0.7 ms step, ~1.8 ms draw. No guessing needed.
  - `argus_noise` being cheap and deterministic per position let me use it as five different
    physical fields (nucleation sites, breath drift, pin field, streak-speed map, micro-slope
    of the film) and store nothing.
  - `float32` state and `steps 3` behaved exactly as §3 documents; the ping-pong needed no
    care beyond "read prev, write next".
- **Cost me time:**
  - **Pacing. This was the whole difficulty of the theme.** My rules were right and my rates
    were ~60–100× too fast: the pane beaded, stretched and merged into a connected "leopard
    lake" lattice within 4 s (`FRAMES=120`), and into a full web by 80 s (my first
    "developed"-state render). I had tuned without a wall-clock reference. What fixed it was
    treating the sim as a conversion: `steps/s = 3 × 30 = 90`, deciding in human time first
    ("a drop should take 1–2 min from visible to running; a streak should cross the pane in
    ~20 s"), then dividing back to per-step constants: COND 0.0040 → 0.00007,
    KC 0.06 → 0.0006, KD 0.05 → 0.004. Detection trick for the same failure: render 120 and
    2700 and compare — if 4 s of sim already shows the end state, everything is too fast.
  - **Contact-line pinning took three models.** (1) Smooth run ramp: *every* drop above the
    ramp crept forever — a pane of frozen teardrops. (2) Sharp threshold: drops pinned, but
    the beading asymptote sat above it, so all drops eventually crossed and the pane
    drained/refilled like weather radar. (3) Shipped: threshold = a static pin field (±12%)
    scaled by (1 − 0.16·wake), with the coarsening asymptote above the *maximum* pin
    threshold and condensation that keeps feeding existing drops. That combination is what
    makes the population self-regulate instead of freezing or boiling. This is physical
    content (pin → threshold → wet path lets go easier → asymptote above max pin), not
    tuning, and it is not obvious.
  - **Lens scale.** My first refraction displaced up to 36 px at every drop edge and the pane
    became smoke-rings: drops read as clutter, not water. Fixed by halving it
    (REFRAC_K 0.20 → 0.15, MAX_OFF 0.06 → 0.045) and gating edge-light by thickness. The
    harness said nothing about this; only looking did.
  - **Busy-machine timing.** Same wall as the convection theme's author: with another agent's harness on a
    core and the app drawing live Spaces, I logged a 10.8 ms paced median and worst frames of
    20–57 ms. A control run of `Tutorial_Reef` spiked to 17 ms worst under the same load, and
    my theme read 7.0–8.6 ms worst / 3.7–5.7 ms paced once the machine was quiet.
  - **A debug pattern worth stealing:** copy the file to a temp path and `sed` the glass layer
    off — `s/const float h0 = s0.r;/const float h0 = 0.0f;/` — to look at the background
    alone; zeroing `REFRAC_K` shows it unwarped. My city went from "invisible" to designed in
    two renders that way.
- **Skill gaps / errors:**
  - §4: *"Render later frames (`FRAMES=900`) for simulations that take time to develop"*
    frames later frames as **validation**. The lesson I needed runs the other way: derive
    rates from wall-clock time *before* authoring them. Proposed addition: *"Design rates in
    human time, then divide by steps/s (30 FPS × your step count: 90 steps/s at 3 steps). A
    wallpaper is watched for minutes. If your drop's whole lifecycle plays out in 0.2 s of
    sim, every gate passes and the wallpaper still looks like a broken tap."*
  - §3: *"Add `float32` for full precision."* Undersells the trap. Half-float's ulp at 1.0 is
    ≈ 1e-3 and my condensation adds ≈ 2e-5 per step — in RGBA16F the water would **round to
    zero and stop accumulating**, with no NaN and no gate to catch it. Proposed addition:
    *"`float32` is not only precision: if a per-step increment is below the half-float ulp at
    your working magnitude (ulp(1.0) ≈ 1e-3), float16 discards it and slow accumulations
    stall silently. A 960×600 float32 RGBA state is 9.2 MB, doubled by the ping-pong;
    precision is cheap to compute and expensive to hold."*
  - §5: *"warm the GPU first (the harness does): the first measurements on a cold GPU run
    slow and fake big differences."* A cold GPU is one failure mode; a **busy** one is the
    other, and it bites agents hardest because agents run in parallel. Proposed addition:
    *"and stop the rest first — the app with live Spaces, other harness runs, a build in a
    sibling worktree. The same unmodified build measured 3.7 → 10.8 ms paced for me while
    another agent's harness ran."*
  - §2's prelude inventory still omits `argus_rand` / `argus_hash` (same note as the entry above).
    I built the entire city — columns, windows, lamps, headlights — on
    `argus_rand(uint2 cell, uint seed)`; it was the most-used function in the theme.
  - The two seeds disagree and authors will trip on it: the **harness** compiles with a pinned
    seed `0x5EED` (watchdog `1`), while the **app** derives it from `(Space id, theme path)`
    (`src/desktop_wallpaper.zig:664`). So the harness shows one composition forever, and the
    app shows a stable composition per Space — a different identity on every Space, which is
    lovely, but it means all my art feedback covered *one* skyline out of many.
  - A datum §5 could carry: 960×600 float32, 3 steps, ~11 neighbourhood reads + 3 noises per
    step → `init/step` measured 0.66–0.81 ms. Authors could then pick state size by
    arithmetic instead of by experiment.
- **Numbers:** Verdict PASS. Watchdog 320×200 PASS. NaN/Inf CLEAN. Pixel variance 2,303,958 /
  2,304,000. Temporal motion 1,019,885 px (min 2,000). Median frame 2.41–2.65 ms back-to-back
  = 0.66–0.81 ms init/step (3 steps) + 1.75–1.84 ms draw; paced 30 FPS 3.6–5.7 ms quiet,
  10.8 ms while another agent's harness ran. Budget 8.33 ms. State 960×600 float32
  (9.2 MB × 2 textures). Zero CPU allocations. M3 class, 1920×1200 + watchdog.
- **Suggestion:** add `--seed N` to the harness (default `0x5EED`, so nothing changes). Every
  part of my composition is hash-derived — skyline, lamp districts, window runs, droplet
  seeding — so one pinned seed means the harness validates exactly **one arrangement of an
  infinite family**, and I could not check that another Space's seed doesn't produce a broken
  skyline (towers off-frame, an empty lamp district). Letting `--seed 0x5EED,1,7,42` render
  four PNGs would make seeded themes testable the way stateless ones already are. Second
  choice, and the one that cost the most time: the pacing paragraph in §4.

> **Addressed 2026-10-16** (branch `claude/theme-skills-v2-c7b50c`). `make harness SEED=N` and
> `--seed N` now exist (Metal, default `0x5EED`), and `tools/theme_sheet.sh` renders four
> moments, three seeds, a 1:1 crop and a flicker count in one go: your FRAMES=2/120/2700 loop,
> made standard. argus-metal-theme now has: §4 "design rates in human time", with your 60–100×
> example and the 150-vs-2700 detection trick; §3 the float16-ulp stall and float32 memory cost;
> §6 the busy-machine warning and your state-step datum; §5 the `sed`-a-layer-off debug pattern;
> §2 the seed model. In the render, the "out of focus" city draws as hard-edged rectangles,
> bokeh discs are cut in half at the skyline, and drops read as grey bubbles. That is in
> `THEME_CRAFT.md` as the missing-photo-reference failure.
