# ARGUS-BENCH cross-model leaderboard: methods

Run on 2026-10-19. Six models in two modes: three runs each, except Gemini 4 Argon's agentic mode,
which has one (see "Argon" below). That makes 34 scored runs. The results are in
[`BENCHMARK.md`](../../BENCHMARK.md) §2, "Cross-model leaderboard". This note says how they were
produced, gives the exact prompts and lists everything that went wrong. Every contestant's file,
last frame, harness reports and run metadata are in
[`bench/results/2026-10-19/`](../../bench/results/2026-10-19/).

**Argon is grading itself.** Argon (Google Gemini) wrote ARGUS-BENCH, the first Argus engine and
the Zig theme SDK (see [`NOTICE.md`](../../NOTICE.md)). Its two rows are therefore a model scored
on a benchmark it wrote. It was run under exactly the same prompts and rules as the other models.

## Setup

| | |
|---|---|
| Date | 2026-10-19. Contestants ran 17:08–18:00 UTC (Claude, Flash) and 18:24–20:55 UTC (Argon). The joint rescore of all 34 finished at 21:03 UTC |
| Repository | main at `8f0a096` for every contestant. The benchmark text (`BENCHMARK.md`, `AGENTS.md`) is the one at that commit |
| Machine | Apple M3, 8 GB, macOS 26.6. Shared: other agent sessions, the Antigravity language server and the owner's own Argus ran throughout (load average 5.4–9.9 during the rescore) |
| Toolchain | the pinned Zig 0.17.0 (`.toolchain/zig`) |
| Claude models | `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-fable-5-1`. The IDs are the ones recorded in each run's transcript |
| Claude harness | Claude Code subagents (`general-purpose`) started with the `model` parameter, default effort. The standalone `claude -p` CLI was not logged in on this machine, and signing in was out of scope |
| Gemini models | `gemini-3.8-flash-high` (the bridge's `flash` alias at its default effort) and `gemini-4-argon-high`, through the local `agy` bridge to the Antigravity CLI (`agy doctor`: HEALTHY). The CLI was 1.4.0 for the Flash runs and had updated itself to 1.4.2 by the Argon runs |
| Which Gemini is "Argon" | The bridge's `pro` alias maps to `gemini-3.1-pro-high`, and the CLI rejects that: `model gemini-3.1-pro-high is not recognized`. The strongest Gemini the CLI lists is Gemini 4 Argon (`gemini-4-argon-{low,medium,high}`), and the high-effort version was used. The table calls it "Gemini 4 Argon (Argon)" because that is the model's own name; it has no "Pro" in it |

## The two modes, as run

**Zero-shot.** Each contestant got `BENCHMARK.md` and the zero-shot prompt from its "How to run it"
section, word for word. It had to answer without compiling or running anything. The full wording
is in [`prompts/zero-shot.md`](../../bench/results/2026-10-19/prompts/zero-shot.md); Argon got the
same text as Flash. The answer was saved and run once through the harness. There were no retries
and no edits by hand. A markdown fence around the answer would have been stripped, but no answer
had one.

**Agentic.** Each contestant got a fresh local clone of `8f0a096` with the pinned Zig linked in.
It then got the benchmark's one-line agentic prompt, after a fixed preamble giving the machine's
rules: work only inside the clone, don't touch Argus.app, don't push, run the harness under
`nice`, stop after about 45 minutes. The text is in
[`prompts/agentic.md`](../../bench/results/2026-10-19/prompts/agentic.md). The bridge enforced a
50-minute limit on the Gemini runs. The submission is the one new `.zig` file in the clone's
`themes/` folder; every clone had exactly one.

## Decisions where the benchmark is ambiguous

Each of these was applied the same way to every model.

1. **"Give the model this file" with no chat window.** A zero-shot contestant could use exactly one
   read (Claude: the prompt file; the Gemini models got the prompt inline) and one write (its
   answer). The transcripts show 17 of the 18 zero-shot runs kept to this. Argon r2 wrote its
   answer twice; the second write replaced the first and is what was scored.
2. **Agentic step 1** (`git clone` from GitHub, `make zig`) was done in advance for every
   contestant: a local clone of the same commit and the same pinned Zig. Network access was not
   part of what was measured.
3. **Scorecard total.** BENCHMARK.md defines a verdict, a frame time and a tier, but no numeric
   total. The total used here is gates passed out of 8. A compile error scores 0, because no gate
   can be evaluated without a build. A theme that compiles but crashes before the report would
   score 1; none did.
4. **Whose numbers count.** Only the rescore described below. The contestants' own reported
   figures are kept in each run's `report.md` and are not used.
5. **Frame time.** All 34 themes and the control were rescored together, in 7 interleaved passes.
   Each pass ran the harness once on every theme, in an order rotated by one per pass, so that load
   from other work spread across the contestants. A run's frame time is the median of its 7 "Avg
   Frame Time" readings. A model's figure is the median and range of its passing runs. The tier is
   the tier of that median. Gates come from pass 1 and were identical in all 7 passes for every
   theme.
6. **"GPU ms".** These are CPU themes. The harness times `step()` and `draw()` on one CPU core,
   and that is the only time reported. No GPU figure exists for a `.zig` theme in this harness.
7. **"Harness runs to first PASS"** (agentic). The §3 skeleton passes by construction, so the
   count is of runs on the contestant's own theme up to its first PASS. A skeleton run is
   recognised by its exact pixel counts (2,300,160 non-background and 2,259,840 animated pixels).
   Counts come from the transcripts, including the CLI's background-task logs for the Gemini runs.
   A command counts only if its output shows the harness ran: two Sonnet runs and one Haiku run had
   commands that stopped at a failed `sed -i` before reaching `make`. All counts agree with the
   contestants' own reports.
8. **Infrastructure failures.** A run that died from a network or service error before the
   contestant handed anything in was re-run from a fresh clone, up to 3 attempts. A run that hits
   the time limit is the contestant's own result, not an infrastructure failure: what it left in
   `themes/` is scored. The Argon section below describes the one place where this rule was broken
   and how that was corrected.
9. **"Best frame" for the contact sheet.** It is chosen by the scorecard, not by eye: a PASS
   first, then the most gates, then the lowest frame time. The tile is that run's frame 120.
10. **Skeleton similarity** (an extra column in the per-run table) is difflib's line ratio between
    the submission and the §3 skeleton. It is there to show when a fast PASS is mostly the
    skeleton.

## Argon (Gemini 4 Argon)

- **One agentic run, not three, because of the owner's Gemini quota.** The owner's Gemini tokens
  ran short, and the owner stopped further Argon calls while agentic r1 was still running. That
  was before any Argon result had been scored, so it was not a choice made by result. So the agentic row is n = 1 and cannot show variance.
- **The counted agentic run is attempt 1, and its file was rebuilt from the transcript.** Attempt 1
  ran into the bridge's 50-minute limit while the agent sat idle, waiting on a background task it
  had started itself. It had written no final report. My driver script wrongly treated that as an
  infrastructure failure: it retried, and each retry deleted the previous clone. Attempts 2 and 3
  also ran the full 50 minutes without a final report. Under the rule above, attempt 1 is the
  run; counting a later attempt would mean picking the best of three. Its theme
  (`Gemini_4_Argon_Relativity.zig`) was rebuilt from the transcript's last full write (step 78);
  the transcript shows no later edit to the file. Rebuilt, it reproduces that attempt's own last
  harness report exactly: allocation size 32,107,216 bytes, 444,918 non-background pixels and
  179,819 animated pixels. Attempts 2 and 3 are not scored, and their files are not in the results.
- **Zero-shot: a service error after the answer.** All three zero-shot calls ended with a service
  error ("The stream was interrupted") after 13–19 minutes. The transcripts show each one had
  already written its complete answer. The answers end with the SDK's `comptime` export block, and
  were scored as they stood.
- **Its own traps.** Two of Argon's three zero-shot answers do not compile, and both errors are
  traps that §4 of BENCHMARK.md lists:
  - r1, line 447: `const kind_sel: u32 = p_idx % 8;`, where `p_idx` is a `usize`.
  - r3, line 116: a local named `u01`, which shadows the primitive type. Trap 5 names `u0` and `u1`.

  The one zero-shot answer that compiles passes all eight gates at 3.78 ms.

## Every run

Frame times are in ms: the median of 7 passes, with the minimum and maximum in brackets.
"Harness runs" are counted from the transcript. "Wall min" is the time the contestant took; for
the Flash runs that needed retries, only the counted attempt.

| Model | Mode | Run | Verdict | Gates | CPU ms/frame (median of 7 passes, min–max) | Tier | Failure | Harness runs (total / to first own PASS) | Wall min | Skeleton sim. |
| :--- | :--- | :---: | :---: | :---: | ---: | :--- | :--- | :---: | ---: | :---: |
| Claude Opus 5.5 | zero-shot | r1 | PASS | 8/8 | 6.63 (4.84–7.35) | Bronze |  | - | 7 | 0.17 |
| Claude Opus 5.5 | zero-shot | r2 | PASS | 8/8 | 1.89 (1.76–2.21) | Gold |  | - | 4 | 0.21 |
| Claude Opus 5.5 | zero-shot | r3 | PASS | 8/8 | 2.19 (1.97–2.87) | Silver |  | - | 4 | 0.19 |
| Claude Opus 5.5 | agentic | r1 | PASS | 8/8 | 2.93 (2.37–5.22) | Silver |  | 7 / 1 | 8 | 0.16 |
| Claude Opus 5.5 | agentic | r2 | PASS | 8/8 | 4.27 (3.47–5.32) | Bronze |  | 10 / 1 | 16 | 0.16 |
| Claude Opus 5.5 | agentic | r3 | PASS | 8/8 | 2.23 (1.65–2.79) | Silver |  | 9 / 1 | 11 | 0.15 |
| Claude Sonnet 5.5 | zero-shot | r1 | PASS | 8/8 | 2.74 (2.18–2.92) | Silver |  | - | 2 | 0.28 |
| Claude Sonnet 5.5 | zero-shot | r2 | PASS | 8/8 | 4.46 (3.19–5.19) | Bronze |  | - | 3 | 0.26 |
| Claude Sonnet 5.5 | zero-shot | r3 | PASS | 8/8 | 4.19 (3.37–5.83) | Bronze |  | - | 3 | 0.33 |
| Claude Sonnet 5.5 | agentic | r1 | PASS | 8/8 | 2.41 (1.90–3.22) | Silver |  | 10 / 1 | 15 | 0.18 |
| Claude Sonnet 5.5 | agentic | r2 | PASS | 8/8 | 2.44 (1.88–2.75) | Silver |  | 8 / 2 | 8 | 0.13 |
| Claude Sonnet 5.5 | agentic | r3 | PASS | 8/8 | 4.91 (3.82–6.84) | Bronze |  | 7 / 2 | 10 | 0.16 |
| Claude Haiku 5.5 | zero-shot | r1 | FAIL | 0/8 | - | - | compile error: expected type 'u32', found 'usize' | - | 6 | 0.23 |
| Claude Haiku 5.5 | zero-shot | r2 | PASS | 8/8 | 1.96 (1.75–2.65) | Gold |  | - | 2 | 0.59 |
| Claude Haiku 5.5 | zero-shot | r3 | PASS | 8/8 | 0.83 (0.71–1.11) | Platinum |  | - | 2 | 0.61 |
| Claude Haiku 5.5 | agentic | r1 | PASS | 8/8 | 6.50 (4.89–7.27) | Bronze |  | 5 / 2 | 3 | 0.24 |
| Claude Haiku 5.5 | agentic | r2 | PASS | 8/8 | 2.84 (2.26–3.40) | Silver |  | 5 / 1 | 3 | 0.31 |
| Claude Haiku 5.5 | agentic | r3 | PASS | 8/8 | 4.69 (3.61–5.22) | Bronze |  | 6 / 2 | 3 | 0.26 |
| Claude Fable 5.1 | zero-shot | r1 | PASS | 8/8 | 3.31 (2.97–3.76) | Silver |  | - | 11 | 0.16 |
| Claude Fable 5.1 | zero-shot | r2 | PASS | 8/8 | 3.77 (3.24–4.29) | Silver |  | - | 5 | 0.26 |
| Claude Fable 5.1 | zero-shot | r3 | PASS | 8/8 | 5.42 (4.32–6.37) | Bronze |  | - | 5 | 0.20 |
| Claude Fable 5.1 | agentic | r1 | PASS | 8/8 | 4.24 (2.99–4.42) | Bronze |  | 9 / 1 | 9 | 0.13 |
| Claude Fable 5.1 | agentic | r2 | PASS | 8/8 | 3.84 (3.41–4.77) | Silver |  | 6 / 1 | 10 | 0.18 |
| Claude Fable 5.1 | agentic | r3 | PASS | 8/8 | 1.85 (1.58–2.16) | Gold |  | 7 / 1 | 19 | 0.17 |
| Gemini 3.8 Flash | zero-shot | r1 | PASS | 8/8 | 11.57 (9.35–12.94) | Bronze |  | - | 4 | 0.24 |
| Gemini 3.8 Flash | zero-shot | r2 | PASS | 8/8 | 1.26 (1.11–1.44) | Gold |  | - | 5 | 0.20 |
| Gemini 3.8 Flash | zero-shot | r3 | PASS | 8/8 | 2.18 (1.66–2.39) | Silver |  | - | 4 | 0.18 |
| Gemini 3.8 Flash | agentic | r1 | PASS | 8/8 | 1.23 (1.06–1.91) | Gold |  | 8 / 2 | 6 | 0.16 |
| Gemini 3.8 Flash | agentic | r2 | PASS | 8/8 | 6.58 (5.80–7.79) | Bronze |  | 14 / 1 | 10 | 0.12 |
| Gemini 3.8 Flash | agentic | r3 | PASS | 8/8 | 11.57 (9.01–15.59) | Bronze |  | 10 / 1 | 12 | 0.15 |
| Gemini 4 Argon (Argon) | zero-shot | r1 | FAIL | 0/8 | - | - | compile error: expected type 'u32', found 'usize' | - | 19 | 0.12 |
| Gemini 4 Argon (Argon) | zero-shot | r2 | PASS | 8/8 | 3.78 (2.96–4.49) | Silver |  | - | 15 | 0.15 |
| Gemini 4 Argon (Argon) | zero-shot | r3 | FAIL | 0/8 | - | - | compile error: name shadows primitive 'u01' | - | 13 | 0.17 |
| Gemini 4 Argon (Argon) | agentic | r1 | PASS | 8/8 | 2.31 (1.93–2.51) | Silver |  | 5 / 2 | 50 | 0.06 |

The control row, the §3 skeleton scored in every pass, read 1.95 ms (median; 1.80–2.25 ms). On an
idle M3 it reads about 1.5 ms.

The agentic contestants' own final figures, against the rescore (ms):

| Run | Own figure | Rescore | | Run | Own figure | Rescore |
|---|---:|---:|---|---|---:|---:|
| Opus r1 | 2.34 | 2.93 | | Sonnet r1 | 1.75 | 2.41 |
| Opus r2 | 3.47 | 4.27 | | Sonnet r2 | 1.88 | 2.44 |
| Opus r3 | 1.63 | 2.23 | | Sonnet r3 | 3.79 | 4.91 |
| Haiku r1 | 4.70 | 6.50 | | Fable r1 | 3.09 | 4.24 |
| Haiku r2 | 9.38–13.73 | 2.84 | | Fable r2 | 3.41 | 3.84 |
| Haiku r3 | 3.71 | 4.69 | | Fable r3 | 1.64 | 1.85 |
| Flash r1 | 0.99 | 1.23 | | Flash r2 | 6.38 | 6.58 |
| Flash r3 | 8.53 | 11.57 | | Argon r1 | 2.44 (last harness log) | 2.31 |

The rescore is slower than 14 of the 16 own figures, by 1.03–1.38×. The machine was busier during
scoring than during most of the contest. The two exceptions are Haiku r2, which measured its own
run while the machine was busier still, and Argon r1, which wrote no final report; its figure here
is its own last harness log. Flash r1 reported "Platinum (987 µs)", which the rescore does not
support (1.23 ms, Gold).

## What failed, and why

- **Haiku 5.5, zero-shot r1: compile error, 0/8.** Line 86 is
  `self.row_base[y] = @as(u32, @intCast((y * GH) / self.h)) * GW;`. `GW` is a `usize`, so the
  product is a `usize`, which cannot be stored in the `u32` field without a cast.
- **Argon, zero-shot r1 and r3: compile errors, 0/8 each.** See the Argon section above.
- **Flash zero-shot, first protocol (not counted).** The first attempt denied Flash every tool
  (`--prompt-permissions`), to match "no tools". Two of the three runs shared a workspace and
  failed with `WORKSPACE_BUSY`, which was my error. The third tried to run a shell command, was
  denied, and returned an empty answer (state `blocked`). The counted runs use the one-write rule
  that the Claude models had, each in its own workspace.
- **Flash agentic: network errors.** r2 failed twice: `write: broken pipe` after 46 s, then again
  after 12.5 min with a half-built theme. Its third attempt completed. r3 failed once
  (`read: operation timed out`, 2 min) and completed on its second attempt.
- **Argon agentic: the 50-minute limit** (see the Argon section).
- **No gate failed in the rescore apart from the three compile errors.** That includes the frame
  budget: the slowest passing runs are Flash zero-shot r1 and agentic r3, both at 11.57 ms.

## Rule breaches and contamination

- **Scratch files outside the clone.** Six of the 12 Claude agentic runs wrote scratch files into
  the session's scratch folder next to their clone instead of inside it: Sonnet r1, Haiku r1,
  Haiku r2, Opus r2, Opus r3 and Fable r3. These were backups, test drivers and variants. The
  transcripts show none touched the repository, the owner's files or Argus. None of it affects
  the score, which is the file left in `themes/`. The bridge's sandbox let the Gemini contestants
  write to their clone, the Zig cache and `/tmp`; their receipts show changes to the theme file
  only, and nothing in the repository. Writes under `/tmp` are not audited.
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
- **A speed ranking.** Within one model and mode, frame times span 1.6–9×. A model with one or
  three runs cannot be separated from its neighbours, and tiers move with the machine's load: in
  the first rescore of 30 runs, Sonnet zero-shot read 4.10 ms (Silver); in this one, 4.19 ms
  (Bronze).
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
