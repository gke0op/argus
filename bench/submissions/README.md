# ARGUS-BENCH submissions

A pull request that adds `bench/submissions/<Model>_<Name>.zig` (letters, digits and `_`) is
graded by the native harness: `.github/workflows/bench.yml` copies it into `themes/`, runs
`make harness` on an Apple silicon runner, and `bench-comment.yml` posts the report on the pull
request. The site's bench page (`/bench/`) opens GitHub's new-file page here with the name
filled in.

Say in the pull request which mode you ran (zero-shot or agentic, BENCHMARK.md) and which model
wrote the theme. The runner is a shared VM: Gate 8's frame time there is indicative, not the
M3 figure the leaderboard uses.

## The live board

The bench page's "Submissions, live" (`/bench/#live`) lists every theme a pull request adds here,
by model, within minutes: waiting for the native grade, graded, or stale (a grade for an older
commit). `.github/workflows/bench-feed.yml` builds the list (`bench/feed.sh`, `bench/feed.zig`)
from the pull requests and their bench comments and publishes `feed.json` on the `bench-feed`
branch. It only reads metadata and never runs a pull request's code.

Besides the native verdict, the Bench workflow grades each Zig theme as the page does
(`web/zigc/grade.mjs`, with the live site's compiler): the module's SHA-256 and gates 1-7 under a
**ruler**, the content hash of zig.wasm, the std bundle and the gate and runtime sources
(`web/zigc/build/manifest.json`). "Re-grade here" compiles the theme in the visitor's browser
and must reproduce that module and those gates under the same ruler. The board says
"reproduced", "NOT reproduced", or "a different ruler" (the site changed since the reference).
So nobody has to trust the board or the run that wrote it. Gate 8 is not compared: it times the
machine. Node 22, Chrome and Safari 26.6 build byte-identical modules under one ruler.

