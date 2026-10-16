## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Kind

- [ ] New theme
- [ ] Theme change
- [ ] Engine
- [ ] Docs

## Theme checklist (skip for engine/docs PRs)

- [ ] One file in `themes/` named `<Author>_<Name>.metal` / `.zig` (plus its data file, if any).
- [ ] `make harness THEME=...` passes; output below.
- [ ] Watched live on a Space for a few minutes: no seams, flicker, banding or drift.
- [ ] Header says what is computed, what is chosen and what is not modelled.
- [ ] Author line in the header, entry in `NOTICE.md`.
- [ ] Any data is redistributable, with its source and licence in the header and `NOTICE.md`.
- [ ] Speed-ups (if any) leave the image unchanged.

## Engine checklist (skip for theme PRs)

- [ ] `make test` passes.
- [ ] Tried with `make run` on a Mac with more than one Space.
- [ ] Before/after cost, paced at 30 FPS for GPU work, if the change could affect it.
- [ ] If it touches theme loading or verification: what it changes in `SECURITY.md`.

## Harness output / numbers

```text

```
