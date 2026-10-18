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
process (`Argus --verify-dylib`, started from Argus's own executable; if Argus can't start it,
the theme is refused, never checked inside Argus) at 320x200 and rejects it if that process:

- does not finish within 10 seconds (Argus then kills it): a theme whose `init`, `step` or
  `draw` never returns can't freeze the app. The heaviest bundled theme, Cygnus A, takes under
  a second, about 2.3 s on efficiency cores alone;
- crashes, or the library is missing the theme entry points;
- reports NaN or Inf in its state;
- allocates memory after `init`;
- writes outside its rows (canary values in the row padding change).

A rejected theme never replaces what a Space shows: the Space keeps the theme it had (with
live reload, the last version of the file that passed; at launch, when it has none yet, the
macOS wallpaper). Argus logs why and shows a note in the menu.

Metal themes are compiled before they replace a Space's current theme, and rejected if they
fail to compile, have no `argus_draw` kernel, or their data file has the wrong size.

Where compiled themes live:

- Argus compiles Zig themes into, and caches verified libraries in,
  `~/Library/Caches/io.github.gke0op.argus/`. That folder is created as yours alone (mode
  0700), and Argus tightens it back if it finds it open to others. Argus refuses the folder if
  it belongs to someone else or is a symlink. Nothing is compiled into or loaded from `/tmp`,
  where any local user could plant a library under a predictable name.
- Argus uses a cached library only if it is a regular file (not a symlink) owned by you that no
  one else can write. Otherwise it compiles and verifies the theme again.
- Release builds ship every bundled Zig theme precompiled inside `Argus.app` (verified when the
  release is built), so a downloaded Argus needs no Zig.

## What the watchdog does not protect against

The watchdog catches **accidents**, so that a broken theme doesn't take the app down. It is
not a sandbox and not a malware scanner:

- The check process runs the theme with your full permissions too. Code in the theme's
  `init`, `step` or `draw` (or in a library constructor) runs during the check.
- It runs one frame at one size. A theme that misbehaves later, at another size, or on a
  condition it chooses, passes.
- The time limit is there for accidents (an endless loop), not for hostile code. Ten seconds
  of the check process is ten seconds of native code running as you, and a theme that is slow
  only when it isn't being checked passes. A theme that hangs after it has been loaded freezes
  Argus; force-quit it and remove the theme.
- It does not look at what the code does: file access, network access and process launches
  are not detected.
- Verified libraries are cached by a hash of the theme's source file, so an unchanged theme is
  not re-checked: a cache hit, or a theme precompiled into the app, loads without running the
  watchdog again. The cache is private to your account (above), so only programs running as
  you can change it, and those could change the theme or Argus itself anyway. The hash covers
  the theme file only, not `argus_theme_sdk.zig` or `src/gpu/`.
- Metal themes are not run before they go live; the harness (`make harness`) is the place to
  test them.

The headless harness (`make harness`) runs the same checks and more, but it also runs the
theme's code on your machine.

## Supported versions

Argus is distributed as source. Security fixes go to the `main` branch; there are no
maintained release branches yet.

## Reporting a vulnerability

Please report vulnerabilities privately, not in a public issue:

- Use GitHub's private vulnerability reporting: open the repository's
  [Security tab](https://github.com/gke0op/argus/security) and choose **Report a vulnerability**
  ([direct link](https://github.com/gke0op/argus/security/advisories/new)). Only the maintainer
  sees the report.

Include what you found, how to reproduce it, and what an attacker could do with it. You can
expect an acknowledgement within 7 days. We will credit you in the fix unless you ask us not
to.

In scope: anything in the Argus engine that lets a theme, a data file, a settings file or a
dropped file do more than this page says it can, or that lets another user on the same Mac
affect what Argus loads. A theme doing harmful things after you chose to run it is expected
behaviour (see above), not a vulnerability, but a theme in *this repository* doing something
harmful is: report it.
