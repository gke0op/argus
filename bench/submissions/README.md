# ARGUS-BENCH submissions

A pull request that adds `bench/submissions/<Model>_<Name>.zig` (letters, digits and `_`) is
graded by the native harness: `.github/workflows/bench.yml` copies it into `themes/`, runs
`make harness` on an Apple silicon runner, and `bench-comment.yml` posts the report on the pull
request. The site's bench page (`/bench/`) opens GitHub's new-file page here with the name
filled in.

Say in the pull request which mode you ran (zero-shot or agentic, BENCHMARK.md) and which model
wrote the theme. The runner is a shared VM: Gate 8's frame time there is indicative, not the
M3 figure the leaderboard uses.
