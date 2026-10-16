# Security

## Themes are programs

An Argus theme is not a picture or a config file. It is code that runs on your Mac with
**your full user permissions**.

- A **Zig theme** (`.zig`) is compiled by Zig into a dynamic library (`.dylib`) and loaded into
  the Argus process. From there it can do anything you can: read and write your files, use the
  network, start other programs. Zig themes are *expected* not to do any of that (the contract
  forbids I/O), but nothing in Argus enforces it.
- A **Metal theme** (`.metal`) is compiled by macOS's Metal compiler and runs as compute
  kernels on your GPU. Kernels cannot make system calls or open files, but a theme can still
  ship a data file that Argus reads from the theme's folder, and a badly written or hostile
  kernel can load the GPU heavily enough to make your Mac sluggish until you remove it.

**Only run themes you trust, from people you trust, after reading them.** A theme is one
file; it is meant to be readable. Treat a theme you download like a shell script you
download.

Some things that run themes without a click:

- **Live reload.** When it is on, Argus recompiles a theme whenever its file changes on disk.
  Anything that can write to that file can change the code Argus runs.
- **Open at login.** When it is on, Argus starts at login (through a per-user LaunchAgent) and
  loads the themes saved in its settings.

## What the watchdog checks

Before a newly compiled Zig theme is loaded into Argus, Argus runs it once in a separate
process (`Argus --verify-dylib`) at 320x200 and rejects it if that process:

- crashes, or the library is missing the theme entry points;
- reports NaN or Inf in its state;
- allocates memory after `init`;
- writes outside its rows (canary values in the row padding change).

Metal themes are compiled before they replace a Space's current theme, and rejected if they
fail to compile, have no `argus_draw` kernel, or their data file has the wrong size.

## What the watchdog does not protect against

The watchdog catches **accidents**, so that a broken theme doesn't take the app down. It is
not a sandbox and not a malware scanner:

- The check process runs the theme with your full permissions too. Code in the theme's
  `init`, `step` or `draw` (or in a library constructor) runs during the check.
- It runs one frame at one size. A theme that misbehaves later, at another size, or on a
  condition it chooses, passes.
- It has no time limit.
- It does not look at what the code does: file access, network access and process launches
  are not detected.
- Verified libraries are cached by a hash of the theme's source, so an unchanged theme is not
  re-checked.
- Metal themes are not run before they go live; the harness (`make harness`) is the place to
  test them.

The headless harness (`make harness`) runs the same checks and more, but it also runs the
theme's code on your machine.

## Supported versions

Argus is distributed as source. Security fixes go to the `main` branch; there are no
maintained release branches yet.

## Reporting a vulnerability

Please report vulnerabilities privately, not in a public issue:

- Email: **<SECURITY CONTACT EMAIL: owner to fill in>**
- or GitHub's private vulnerability reporting on this repository ("Report a vulnerability"
  under the Security tab), if it is enabled.

Include what you found, how to reproduce it, and what an attacker could do with it. You can
expect an acknowledgement within <N> days. We will credit you in the fix unless you ask us not
to.

In scope: anything in the Argus engine that lets a theme, a data file, a settings file or a
dropped file do more than this page says it can, or that lets another user on the same Mac
affect what Argus loads. A theme doing harmful things after you chose to run it is expected
behaviour (see above), not a vulnerability, but a theme in *this repository* doing something
harmful is: report it.
