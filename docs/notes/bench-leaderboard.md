# ARGUS-BENCH cross-model leaderboard: methods

Run on 2026-10-19. Five models, two modes, three runs each: 30 runs. The results are in
[`BENCHMARK.md`](../../BENCHMARK.md) §2, "Cross-model leaderboard". This note says how they were
produced, gives the exact prompts and lists everything that went wrong. Every contestant's file,
last frame, harness reports and run metadata are in
[`bench/results/2026-10-19/`](../../bench/results/2026-10-19/).

## Setup

| | |
|---|---|
| Date | 2026-10-19. Contestants ran 17:08–18:00 UTC; scoring finished 18:10 UTC |
| Repository | main at `8f0a096`. The benchmark text (`BENCHMARK.md`, `AGENTS.md`) is the one at that commit |
| Machine | Apple M3, 8 GB, macOS 26.6. Shared: other agent sessions, the Antigravity language server and the owner's own Argus ran throughout (load average 5.6–6.9 while scoring) |
| Toolchain | the pinned Zig 0.17.0 (`.toolchain/zig`) |
| Claude models | `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-fable-5-1`. The IDs are the ones recorded in each run's transcript |
| Claude harness | Claude Code subagents (`general-purpose`) started with the `model` parameter, default effort. The standalone `claude -p` CLI was not logged in on this machine, and signing in was out of scope |
| Gemini model | `gemini-3.8-flash-high` (the bridge's `flash` alias at its default effort), through the local `agy` bridge to the Antigravity CLI 1.4.0 (`agy doctor`: HEALTHY) |

## The two modes, as run

**Zero-shot.** Each contestant got `BENCHMARK.md` and the zero-shot prompt from its "How to run it"
section, word for word. It had to answer without compiling or running anything. The full wording
is in [`prompts/zero-shot.md`](../../bench/results/2026-10-19/prompts/zero-shot.md). The answer
was saved and run once through the harness. There were no retries and no edits by hand. A
markdown fence around the answer would have been stripped, but no answer had one.

**Agentic.** Each contestant got a fresh local clone of `8f0a096` with the pinned Zig linked in.
It then got the benchmark's one-line agentic prompt, after a fixed preamble giving the machine's
rules: work only inside the clone, don't touch Argus.app, don't push, run the harness under
`nice`, stop after about 45 minutes. The text is in
[`prompts/agentic.md`](../../bench/results/2026-10-19/prompts/agentic.md). The submission is the
one new `.zig` file in the clone's `themes/` folder; every clone had exactly one.

## Decisions where the benchmark is ambiguous

Each of these was applied the same way to every model.

1. **"Give the model this file" with no chat window.** A zero-shot contestant could use exactly one
   read (Claude: the prompt file; Flash got the prompt inline) and one write (its answer). The
   transcripts show that all 15 zero-shot runs kept to this: Claude used `Read`, `Write` and the
   hand-back only; Flash used one `write_to_file`.
2. **Agentic step 1** (`git clone` from GitHub, `make zig`) was done in advance for every
   contestant: a local clone of the same commit and the same pinned Zig. Network access was not
   part of what was measured.
3. **Scorecard total.** BENCHMARK.md defines a verdict, a frame time and a tier, but no numeric
   total. The total used here is gates passed out of 8. A compile error scores 0, because no gate
   can be evaluated without a build. A theme that compiles but crashes before the report would
   score 1; none did.
4. **Whose numbers count.** Only the rescore described below. The contestants' own reported
   figures are kept in each run's `report.md` and are not used.
5. **Frame time.** Each theme was scored in 7 interleaved passes: each pass ran the harness once
   on every theme, in an order rotated by one per pass, so that load from other work spread
   across the contestants. A run's frame time is the median of its 7 "Avg Frame Time" readings.
   A model's figure is the median and range of its passing runs. The tier is the tier of that
   median. Gates come from pass 1 and were identical in all 7 passes for every theme.
6. **"GPU ms".** These are CPU themes. The harness times `step()` and `draw()` on one CPU core,
   and that is the only time reported. No GPU figure exists for a `.zig` theme in this harness.
7. **"Harness runs to first PASS"** (agentic). The §3 skeleton passes by construction, so the
   count is of runs on the contestant's own theme up to its first PASS. A skeleton run is
   recognised by its exact pixel counts (2,300,160 non-background and 2,259,840 animated pixels).
   Counts come from the transcripts. A command counts only if its output shows the harness ran:
   two Sonnet runs and one Haiku run had commands that stopped at a failed `sed -i` before
   reaching `make`. All counts agree with the contestants' own reports.
8. **Infrastructure failures.** A run that died from a network or service error before the
   contestant handed anything in was re-run from a fresh clone, up to 3 attempts. A run that
   failed every attempt would have been reported as an infrastructure failure and not scored;
   none did.
9. **"Best frame" for the contact sheet.** It is chosen by the scorecard, not by eye: a PASS
   first, then the most gates, then the lowest frame time. The tile is that run's frame 120.
10. **Skeleton similarity** (an extra column in the per-run table) is difflib's line ratio between
    the submission and the §3 skeleton. It is there to show when a fast PASS is mostly the
    skeleton.

## Every run

Frame times are in ms: the median of 7 passes, with the minimum and maximum in brackets.
"Harness runs" are counted from the transcript. "Wall min" is the time the contestant took; for
the Flash runs that needed retries, only the counted attempt.

| Model | Mode | Run | Verdict | Gates | CPU ms/frame (median of 7 passes, min–max) | Tier | Failure | Harness runs (total / to first own PASS) | Wall min | Skeleton sim. |
| :--- | :--- | :---: | :---: | :---: | ---: | :--- | :--- | :---: | ---: | :---: |
| Claude Opus 5.5 | zero-shot | r1 | PASS | 8/8 | 6.83 (5.87–11.14) | Bronze |  | - | 7 | 0.17 |
| Claude Opus 5.5 | zero-shot | r2 | PASS | 8/8 | 1.89 (1.68–3.09) | Gold |  | - | 4 | 0.21 |
| Claude Opus 5.5 | zero-shot | r3 | PASS | 8/8 | 2.32 (1.76–3.43) | Silver |  | - | 4 | 0.19 |
| Claude Opus 5.5 | agentic | r1 | PASS | 8/8 | 2.72 (2.57–3.61) | Silver |  | 7 / 1 | 8 | 0.16 |
| Claude Opus 5.5 | agentic | r2 | PASS | 8/8 | 4.52 (3.69–6.65) | Bronze |  | 10 / 1 | 16 | 0.16 |
| Claude Opus 5.5 | agentic | r3 | PASS | 8/8 | 2.40 (1.75–3.05) | Silver |  | 9 / 1 | 11 | 0.15 |
| Claude Sonnet 5.5 | zero-shot | r1 | PASS | 8/8 | 2.68 (2.41–4.02) | Silver |  | - | 2 | 0.28 |
| Claude Sonnet 5.5 | zero-shot | r2 | PASS | 8/8 | 4.10 (3.73–4.86) | Silver |  | - | 3 | 0.26 |
| Claude Sonnet 5.5 | zero-shot | r3 | PASS | 8/8 | 4.55 (3.85–14.87) | Bronze |  | - | 3 | 0.33 |
| Claude Sonnet 5.5 | agentic | r1 | PASS | 8/8 | 2.92 (2.06–4.11) | Silver |  | 10 / 1 | 15 | 0.18 |
| Claude Sonnet 5.5 | agentic | r2 | PASS | 8/8 | 2.60 (2.06–3.61) | Silver |  | 8 / 2 | 8 | 0.13 |
| Claude Sonnet 5.5 | agentic | r3 | PASS | 8/8 | 6.07 (4.96–7.27) | Bronze |  | 7 / 2 | 10 | 0.16 |
| Claude Haiku 5.5 | zero-shot | r1 | FAIL | 0/8 | - | - | compile error: expected type 'u32', found 'usize' | - | 6 | 0.23 |
| Claude Haiku 5.5 | zero-shot | r2 | PASS | 8/8 | 2.19 (1.95–2.50) | Silver |  | - | 2 | 0.59 |
| Claude Haiku 5.5 | zero-shot | r3 | PASS | 8/8 | 1.03 (0.87–1.34) | Gold |  | - | 2 | 0.61 |
| Claude Haiku 5.5 | agentic | r1 | PASS | 8/8 | 6.69 (6.33–7.24) | Bronze |  | 5 / 2 | 3 | 0.24 |
| Claude Haiku 5.5 | agentic | r2 | PASS | 8/8 | 2.98 (2.33–3.66) | Silver |  | 5 / 1 | 3 | 0.31 |
| Claude Haiku 5.5 | agentic | r3 | PASS | 8/8 | 5.38 (4.26–6.13) | Bronze |  | 6 / 2 | 3 | 0.26 |
| Claude Fable 5.1 | zero-shot | r1 | PASS | 8/8 | 3.58 (3.21–4.85) | Silver |  | - | 11 | 0.16 |
| Claude Fable 5.1 | zero-shot | r2 | PASS | 8/8 | 3.96 (3.40–4.97) | Silver |  | - | 5 | 0.26 |
| Claude Fable 5.1 | zero-shot | r3 | PASS | 8/8 | 5.83 (4.50–8.21) | Bronze |  | - | 5 | 0.20 |
| Claude Fable 5.1 | agentic | r1 | PASS | 8/8 | 4.42 (3.27–5.76) | Bronze |  | 9 / 1 | 9 | 0.13 |
| Claude Fable 5.1 | agentic | r2 | PASS | 8/8 | 5.45 (4.64–6.86) | Bronze |  | 6 / 1 | 10 | 0.18 |
| Claude Fable 5.1 | agentic | r3 | PASS | 8/8 | 2.08 (1.82–2.77) | Silver |  | 7 / 1 | 19 | 0.17 |
| Gemini 3.8 Flash | zero-shot | r1 | PASS | 8/8 | 11.56 (10.76–14.31) | Bronze |  | - | 4 | 0.24 |
| Gemini 3.8 Flash | zero-shot | r2 | PASS | 8/8 | 1.47 (0.92–1.89) | Gold |  | - | 5 | 0.20 |
| Gemini 3.8 Flash | zero-shot | r3 | PASS | 8/8 | 2.26 (1.93–2.54) | Silver |  | - | 4 | 0.18 |
| Gemini 3.8 Flash | agentic | r1 | PASS | 8/8 | 1.70 (1.15–2.09) | Gold |  | 8 / 2 | 6 | 0.16 |
| Gemini 3.8 Flash | agentic | r2 | PASS | 8/8 | 6.76 (5.51–9.02) | Bronze |  | 14 / 1 | 10 | 0.12 |
| Gemini 3.8 Flash | agentic | r3 | PASS | 8/8 | 11.04 (9.52–14.20) | Bronze |  | 10 / 1 | 12 | 0.15 |

The control row, the §3 skeleton scored in every pass, read 1.93 ms (median; 1.78–7.34 ms). On an
idle M3 it reads about 1.5 ms. The 7.34 ms reading was a single busy moment.

The agentic contestants' own final figures, against the rescore (ms):

| Run | Own figure | Rescore | | Run | Own figure | Rescore |
|---|---:|---:|---|---|---:|---:|
| Opus r1 | 2.34 | 2.72 | | Sonnet r1 | 1.75 | 2.92 |
| Opus r2 | 3.47 | 4.52 | | Sonnet r2 | 1.88 | 2.60 |
| Opus r3 | 1.63 | 2.40 | | Sonnet r3 | 3.79 | 6.07 |
| Haiku r1 | 4.70 | 6.69 | | Fable r1 | 3.09 | 4.42 |
| Haiku r2 | 9.38–13.73 | 2.98 | | Fable r2 | 3.41 | 5.45 |
| Haiku r3 | 3.71 | 5.38 | | Fable r3 | 1.64 | 2.08 |
| Flash r1 | 0.99 | 1.70 | | Flash r2 | 6.38 | 6.76 |
| Flash r3 | 8.53 | 11.04 | | | | |

The rescore is slower than 14 of the 15 own figures, by 1.06–1.72×. The machine was busier during
scoring than during most of the contest. Haiku r2 measured its own run while it was busier still.
Flash r1 reported "Platinum (987 µs)", which the rescore does not support (1.70 ms, Gold).

## What failed, and why

- **Haiku 5.5, zero-shot r1: compile error, 0/8.** Line 86 is
  `self.row_base[y] = @as(u32, @intCast((y * GH) / self.h)) * GW;`. `GW` is a `usize`, so the
  product is a `usize`, which cannot be stored in the `u32` field without a cast. This is the
  class of integer-width trap that §4 of BENCHMARK.md warns about.
- **Flash zero-shot, first protocol (not counted).** The first attempt denied Flash every tool
  (`--prompt-permissions`), to match "no tools". Two of the three runs shared a workspace and
  failed with `WORKSPACE_BUSY`, which was my error. The third tried to run a shell command, was
  denied, and returned an empty answer (state `blocked`). The counted runs use the one-write rule
  that the Claude models had, each in its own workspace.
- **Flash agentic: network errors.** r2 failed twice: `write: broken pipe` after 46 s, then again
  after 12.5 min with a half-built theme. Its third attempt completed. r3 failed once
  (`read: operation timed out`, 2 min) and completed on its second attempt. The failed receipts
  are not committed; the errors are quoted here.
- **No gate failed in the rescore except the one compile error.** That includes the frame budget:
  the slowest passing run is Flash zero-shot r1 at 11.56 ms.

## Rule breaches and contamination

- **Scratch files outside the clone.** Six of the 12 Claude agentic runs wrote scratch files into
  the session's scratch folder next to their clone instead of inside it: Sonnet r1, Haiku r1,
  Haiku r2, Opus r2, Opus r3 and Fable r3. These were backups, test drivers and variants. The
  transcripts show none touched the repository, the owner's files or Argus. None of it affects
  the score, which is the file left in `themes/`. The bridge's sandbox let Flash write to its clone, the Zig
  cache and `/tmp`; its receipts show changes to its theme file only, and nothing in the repository.
  Writes under `/tmp` are not audited.
- **Heavy runs.** Sonnet r1 ran several harness runs of 12,000–60,000 frames while the others
  were working. Several contestants did long stability runs. That load affected the other
  contestants' own timings, but not the rescore, which ran after every contestant had finished.
- **Global instructions leaked in.** On this machine, both harnesses load the owner's global agent
  instructions: Claude Code from `~/.claude/CLAUDE.md`, Antigravity from `~/.gemini/GEMINI.md`.
  These cover memory folders, an integrity checklist and session rituals, not themes. The
  preambles told contestants to ignore them, but several Claude reports still end with that
  checklist ("Five checks") and declared shortcuts. Every model of a given harness got the same
  context. A clean run would use a fresh account with no global instructions.
- **Concurrency.** Up to five contestants ran at once (at most one per model), so every agentic
  contestant measured its own timings on a busy machine. The rescore removes that from the table.

## What this does not show

- **Quality.** The harness checks that a theme runs; it does not check what it shows. Look at the
  frames. Haiku's two passing zero-shot answers (skeleton similarity 0.59 and 0.61) are a ring
  pattern and a palette cycle over a precomputed spiral. Neither simulates a system, yet they are
  the fastest zero-shot themes.
- **A speed ranking.** Within one model and mode, frame times span 1.6–8×. Three runs are enough
  to show that, not to separate the medians.
- **Live cost.** In Argus a theme steps at the app's pace, not the harness's `dt = 0.008` every
  frame. Several agentic contestants note that their live per-frame cost will differ. Nothing
  here was run live.

## Reproduce

```sh
python3 bench/score.py bench/results/2026-10-19 --repeats 7     # rescore every theme (serial, nice)
python3 bench/leaderboard.py bench/results/2026-10-19           # the BENCHMARK.md table
python3 bench/leaderboard.py bench/results/2026-10-19 --runs    # the per-run table above
python3 bench/contact_sheet.py bench/results/2026-10-19 docs/media/bench-leaderboard.png
```

The contestants' transcripts are not committed. They hold the machine's local paths and the owner's
global instructions. Each run's `meta.json` keeps what was taken from its transcript: the model ID,
the tool calls, the harness-run counts and the wall time.
