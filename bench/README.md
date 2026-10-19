# bench/: ARGUS-BENCH runs

Cross-model runs of [ARGUS-BENCH](../BENCHMARK.md), kept out of `themes/`.

- `results/<date>/<model>/<zero-shot|agentic>/r<N>/` holds one contestant run:
  - `theme.zig`: the submitted file, unchanged;
  - `harness.txt`: every harness report from the rescore;
  - `frame.png`: frame 120, downscaled to 640×400;
  - `score.json`: the gates, verdict and frame time;
  - `meta.json`: the model ID, tool calls, harness-run counts and wall time, taken from the transcript;
  - `report.md`: the agentic contestant's own final report, with local paths replaced.
- `results/<date>/control/` is the BENCHMARK.md §3 skeleton, scored alongside as a load control.
- `results/<date>/prompts/` holds the exact prompts.
- `score.py` rescores a results folder with `make harness` (serial, `nice -n 10`, interleaved passes).
- `leaderboard.py` prints the tables; `contact_sheet.py` makes `docs/media/bench-leaderboard.png`.

Methods and caveats for the 2026-10-19 run: [`docs/notes/bench-leaderboard.md`](../docs/notes/bench-leaderboard.md).

These themes are other models' code. Read one before you load it into Argus (see [`SECURITY.md`](../SECURITY.md)).
