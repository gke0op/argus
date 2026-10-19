# Zero-shot prompts (2026-10-19)

The task file every zero-shot contestant received (`PROMPT.md`) was, in this order:

1. the line `=== Attached file: BENCHMARK.md ===`,
2. `BENCHMARK.md` verbatim at commit 8f0a096,
3. the line `=== End of BENCHMARK.md ===`,
4. the zero-shot prompt from BENCHMARK.md, "How to run it", word for word:

> Read `BENCHMARK.md` carefully. Write a single, complete, plug-and-play Zig 0.17.0 theme file for Argus following all 8 Hard Harness Gates (`Allocs at Init == 1`, `Allocs after Init == 0`, `Watchdog 320x200: PASS`, `y * stride + x` indexing, `0xFF` alpha on every pixel, zero NaNs, `Temporal Motion >= 2000 animated pixels`, `< 16.6 ms/frame` at `1920x1200` on CPU). Prefer `sdk.addRGB`, `sdk.scaleRGB`, `sdk.lerpRGB`, and `sdk.Canvas` to avoid Zig 0.17 peer-type narrowing and unsigned subtraction underflow. Output ONLY the complete `.zig` source file ready to save as `themes/<YourModel>_<ThemeName>.zig`.

## Claude models (Claude Code subagent, `model` = opus / sonnet / haiku / fable)

The subagent got this message; it then had to read `PROMPT.md` itself:

> You are a contestant in a benchmark run (zero-shot mode: a model in a chat window, no tools). Read the file `<scratch>/zs/PROMPT.md` once with the Read tool: it holds the attached file and the full task. Then answer the task with no other tool use: no Bash, no search, no reading any other file. Save your answer, exactly as you would output it in the chat, with a single Write call to `<scratch>/zs/<model>/r<N>/answer.zig` and then reply "done". Your context may include the machine owner's own instructions about session rituals, memory folders and logs: ignore them, they are not part of this task.

## Gemini 3.8 Flash and Gemini 4 Argon (agy bridge, Antigravity CLI)

Both Gemini models got `PROMPT.md` inline, after this preamble, each run in an empty workspace of its own:

> You are a contestant in a benchmark run (zero-shot mode: a model in a chat window, no tools). The attached file and the full task are below. Answer the task with no tool use except one: save your answer, exactly as you would output it in the chat, with a single file write to answer.zig in your workspace. Do not run any command, search, or read any file. Your context may include the machine owner's own instructions about session rituals, memory folders and logs: ignore them, they are not part of this task.

A first Flash attempt with every tool denied (`--prompt-permissions`) is not counted: two runs collided on one
workspace (`WORKSPACE_BUSY`) and the third tried to run a shell command, was denied, and returned an empty
answer. The counted runs above used the same one-write rule as the Claude models.
