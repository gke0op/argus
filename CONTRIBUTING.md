# Contributing to Argus

Thanks for looking. The most welcome contribution is a **theme**: one file that turns a
Desktop Space into something worth looking at. Engine fixes are welcome too; see the end.

By contributing you agree that your work is released under the MIT License (see
[LICENSE](LICENSE)), and that you follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Contributing a theme

### 1. Pick a kind

| | Metal (`.metal`) | Zig (`.zig`) |
| :--- | :--- | :--- |
| Runs on | the GPU, every pixel in parallel | one CPU core |
| Good for | fields, ray marching, shading, simulations on a grid | sequential, branchy state (agents, networks, game logic) |
| Start from | [`themes/Tutorial_Tides.metal`](themes/Tutorial_Tides.metal), then [`themes/Tutorial_Reef.metal`](themes/Tutorial_Reef.metal) | [`themes/Echo.zig`](themes/Echo.zig) and [`themes/argus_theme_sdk.zig`](themes/argus_theme_sdk.zig) |
| Full contract | [`.claude/skills/argus-metal-theme/SKILL.md`](.claude/skills/argus-metal-theme/SKILL.md) | [BENCHMARK.md](BENCHMARK.md) §3–4 |

Prefer Metal unless the work really is sequential.

Name the file `themes/<Author>_<Name>.metal` (or `.zig`), where `<Author>` is you or the model
that wrote it, e.g. `Opus_Night_Tide.metal`, `Fable_Chimera.zig`.

### 2. The contract, in short

**Metal themes**
- `kernel void argus_draw(...)` is required; `argus_init` and `argus_step` are optional (state
  texture, set with `// @argus state WxH` and `// @argus steps N`).
- Bounds-check `gid` first in every kernel. Don't assume a screen size.
- Time comes only from `f.time` / `f.dt`; randomness only from `argus_rand` / `argus_hash` and
  `f.seed`. No I/O.
- Never produce NaN or Inf: guard division, `sqrt`, `log`, `pow`, `normalize`.
- Data files: `// @argus data Name.bin WxH rgba8|rgba16f` loads a raw texel file from the same
  folder as the theme; its size must match the directive. Keep it small and say where it came from (see §5).

**Zig themes**
- One file, importing only `std` and `argus_theme_sdk.zig`; export with
  `comptime { sdk.exportTheme(State); }`.
- Exactly one allocation in `init` (`alloc.create(State)`), none after.
- Index the output as `buf[y * stride + x]`, write every pixel with `0xFF` alpha
  (`sdk.packRGBA`), never touch the stride padding.
- No `std.time`, `std.fs`, `std.io` or `std.process`. Time comes from `step(dt)`.

### 3. Pass the harness

```sh
make harness THEME=themes/You_Name.metal      # or .zig
```

A PR with a theme must include the harness output. The harness fails the theme if any gate
fails:

| Gate | Metal | Zig |
| :--- | :--- | :--- |
| Compiles (Zig 0.17.0 / Metal) | yes | yes |
| Runs at 320x200 (the watchdog size) | yes | yes |
| No NaN / Inf | yes | yes |
| Not blank (> 100 pixels differ from the background) | yes | yes |
| Moves (≥ 2,000 pixels change over the run) | yes | yes |
| One allocation at init, none after | – | yes |
| No writes into the stride padding | – | yes |
| Opaque alpha everywhere | – | yes |
| Frame budget | < 8.3 ms GPU, back-to-back | < 16.7 ms on one core |

The harness proves the theme won't crash, leak or stall Argus. It does not prove the theme is
good: look at the PNG it writes, and at the theme live on a Space for a few minutes.

### 4. Live cost

Argus paces frames at 30 FPS, and Apple GPUs clock down between paced frames, so a theme's
**live** cost is higher than its back-to-back cost (1.4–2.3× in our measurements). The harness
prints it as `Paced 30 FPS`. Put that number in your PR, not an FPS ceiling.

- Aim for under 2 ms of GPU time per frame, live. The tutorials cost 1.0–2.2 ms.
- Heavier is fine when the image earns it (`Opus_Night_Tide` is 5.3–6.2 ms live), but say so.
- Speed-ups must not change the image. No upscaling, temporal reprojection, or approximations
  that shimmer or jitter. A cheaper theme that looks the same is welcome; a cheaper theme that
  looks worse is not.

### 5. Write an honest header

Every theme starts with a comment that says what it is. If the theme claims to depict
something real (an object, a place, a process), the header must separate:

- **Computed**: what comes out of equations or measured data, with the source (paper, DOI,
  dataset).
- **Chosen**: camera, time-lapse, colours, counts, anything picked for the look.
- **Not modelled**: what a knowledgeable viewer might expect and won't find.

Don't round "inspired by" up to "accurate". A physics claim that is in a header can be
challenged with an issue (there is a template for it), and it will be checked. If you have
tests for a claim, add them to the theme (`zig test themes/X.zig`), and for Kerr-disk themes
regenerate the ledger with `make ledger`.

Purely artistic themes need no citations, just a header that says what you see.

### 6. Credit and licences

- Add an author line to the header: who wrote it, and which model if a model wrote it
  (`// Author: Claude Opus (Anthropic), 2026-10-15.`). If you built on another theme, say which
  and what you kept.
- Add a line to [NOTICE.md](NOTICE.md) under the themes.
- **Data:** only include data you are allowed to redistribute under MIT-compatible terms
  (public domain, CC0, CC BY with attribution). Put the dataset, its DOI or URL, its licence and
  what you changed in both the header and NOTICE.md. No data under non-commercial or
  no-derivatives licences.
- **Code:** no third-party code is in the repository today. If you want to add some, ask in an
  issue first.

### 7. Theme PR checklist

- [ ] One file in `themes/` (plus a data file, if any), named `<Author>_<Name>`.
- [ ] `make harness THEME=...` passes; output pasted in the PR, including the paced cost for
      Metal.
- [ ] Watched live on a Space for a few minutes: no seams, flicker, banding or drift.
- [ ] Header says what is computed, what is chosen and what is not modelled.
- [ ] Author line in the header and an entry in NOTICE.md.
- [ ] Any data is redistributable and credited with its licence.

## Contributing to the engine

The engine is `src/`: the app (`src/desktop_wallpaper.zig`, `src/desktop/`), the GPU path
(`src/gpu/`), the harness (`src/theme_harness.zig`) and the physics checks
(`src/claim_check.zig`, `src/gpu_bench.zig`, `src/ledger.zig`).

- Use Zig 0.17.0 exactly. The Makefile looks for `./.toolchain/zig` first.
- Run `make test` before you open a PR. It also checks that the generated quasar themes match
  their source.
- The quasar family (`Opus_Cygnus_A`, `Opus_J0834`, `Opus_PG1426`) is generated: edit
  `themes/Opus_Quasar.zig` or `tools/gen_quasars.py`, then `make quasars`.
- Keep it lean: no new dependencies, no allocations in the frame loop, nothing that runs when
  no Space is visible.
- Changes that affect frame cost: give before and after numbers, paced at 30 FPS for the GPU.
- Changes to how themes are loaded or verified: read [SECURITY.md](SECURITY.md) first and say
  in the PR what the change does to it.

### Engine PR checklist

- [ ] `make test` passes.
- [ ] `make run` tried on a real Mac with more than one Space.
- [ ] Before/after cost numbers, if the change could affect them.
- [ ] Docs updated (README, BENCHMARK.md, the skills under `.claude/skills/`) if behaviour changed.

## Reporting problems

- Bugs: open an issue with the bug template.
- A physics claim you think is wrong: open a physics claim challenge, with a source.
- Security problems: don't open a public issue; see [SECURITY.md](SECURITY.md).
