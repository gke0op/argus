# Installing Argus

Argus runs on a Mac with Apple silicon (arm64). It was tested on macOS 26.6 Tahoe, and the
app asks for macOS 13 or later.

## One command

```bash
curl -fsSL https://raw.githubusercontent.com/gke0op/argus/main/install.sh | sh
```

[`install.sh`](../install.sh) downloads the latest release zip and its `.sha256` from GitHub
Releases, refuses to install if they don't match, puts the folder at `~/Applications/Argus`
and opens `Argus.app`. A file that `curl` downloads isn't marked "downloaded from the
internet", so macOS opens the app without the approval steps below; only do this for software
you trust. Run it again to update: your settings and your own themes stay, and a shipped theme
you edited is kept as `themes/<name>.before-<version>`. `ARGUS_DIR=<folder>` installs
somewhere else; `ARGUS_VERSION=0.1.3` picks a release.

## Download a release (nothing else to install)

1. Download `Argus-v<version>-macos-arm64.zip` (currently `Argus-v0.1.3-macos-arm64.zip`)
   from the project's GitHub Releases page. To check it, download the `.sha256` file next to
   it and run `shasum -a 256 -c Argus-v<version>-macos-arm64.zip.sha256` in the same folder.
2. Double-click the zip. You get a folder `Argus-v<version>-macos-arm64` that holds `Argus.app`
   and `themes/`. **Keep them together.** Argus loads themes from the folder it sits in and
   saves its settings there (`.argus_spaces.conf`, `.argus_settings.conf`). You can move or
   rename the whole folder, for example to `~/Applications/Argus`, before you open the app.
3. Open the app once using one of the two ways below. Argus is ad-hoc signed and not notarized:
   it is an open-source project without an Apple Developer ID. So the first time you open it,
   macOS says it cannot check the app for malware and will not open it. Pick one way:

   **A. One Terminal command (tested).** This removes the "downloaded from the internet"
   mark from the folder, so macOS opens it like an app you built yourself:

   ```bash
   V=0.1.3   # the version you downloaded
   xattr -dr com.apple.quarantine ~/Downloads/Argus-v$V-macos-arm64
   open ~/Downloads/Argus-v$V-macos-arm64/Argus.app
   ```

   Use the folder's real path if you moved it. Only do this for software you trust. You can
   read the source and build it yourself instead (below).

   **B. System Settings** (Apple's steps for
   [macOS Tahoe 26](https://support.apple.com/guide/mac-help/mh40616/26/mac/26), see also
   [Safely open apps on your Mac](https://support.apple.com/en-us/102445)):
   1. Double-click `Argus.app`. When macOS says it cannot verify "Argus", click **Done**
      (not Move to Trash).
   2. Open Apple menu > System Settings > **Privacy & Security** and scroll down to Security.
      Next to the message that "Argus" was blocked, click **Open Anyway**. The button is
      there for about an hour after you tried to open the app.
   3. Enter your login password and click **Open** in the dialog that follows.

   macOS then remembers the exception, and Argus opens with a double-click from then on.
   Since macOS 15 Sequoia, Control-click > Open no longer skips this check
   ([Apple developer news, Aug 2024](https://developer.apple.com/news/?id=saqachfa)).

4. Click the eye in the menu bar to pick a theme for each Desktop Space. Double-click a
   thumbnail (or tap it with two fingers) to eject its theme and return that Space to the
   macOS default. To start Argus when you log in, turn on **Open at login** in its Settings.

   **Can't see the eye?** On a MacBook with a notch, macOS hides the menu-bar items that don't
   fit, and the eye can be one of them. Open `Argus.app` again (double-click it in Finder, or
   `open Argus.app`): the running Argus shows its popover centred under the menu bar and
   resumes if it was paused; no second copy starts. To get the eye back, quit a few other
   menu-bar apps; once it shows, hold ⌘ and drag it to the right so it keeps its place.

### What works without Zig

Every theme in the release works with no developer tools:

- **`.zig` themes** ship precompiled and verified inside the app
  (`Argus.app/Contents/Resources/prebuilt`), one per theme, keyed by a hash of the theme
  file's contents.
- **`.metal` themes** are compiled at run time by the Metal framework that comes with macOS.
  This needs neither Xcode nor the Command Line Tools.

You need **Zig 0.17.0** only to edit a `.zig` theme or add a new one. A changed file no longer
matches its precompiled copy, so Argus compiles it. If Zig is missing, the menu says
"*Theme* needs Zig 0.17.0 to build". To install Zig, run `brew install zig` (Homebrew's `zig` is
0.17.0), or download it from [ziglang.org](https://ziglang.org/download/). Argus looks for
`./.toolchain/zig` next to the app, then `zig` on PATH, then `/opt/homebrew/bin/zig` and
`/usr/local/bin/zig`. Editing a `.metal` theme needs nothing extra.

### Uninstall

Quit Argus from its menu and turn off **Open at login** first, or delete
`~/Library/LaunchAgents/io.github.gke0op.argus.plist`. Then delete the folder. Compiled themes are cached in
`~/Library/Caches/io.github.gke0op.argus`; delete that folder too.

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`) for `git`, `make` and `codesign`,
plus Zig 0.17.0, the release of 2026-10-01 that `build.zig.zon` pins:

```bash
git clone https://github.com/gke0op/argus.git
cd argus
make zig     # installs Zig 0.17.0 into .toolchain/ (SHA-256 checked)
make test
make run     # builds Argus.app and starts it
```

`make zig` (`tools/get-zig.sh`) downloads
`https://ziglang.org/download/0.17.0/zig-aarch64-macos-0.17.0.tar.xz` and checks it against
the SHA-256 published in <https://ziglang.org/download/index.json>
(`b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a`). If `minisign` is
installed, it also checks the signature against Zig's public key. Homebrew works too:
`brew install zig` installs 0.17.0, and the Makefile uses it when `.toolchain/zig` is absent.

Other targets:

| Command | What it does |
| --- | --- |
| `make check-themes` | Runs the headless harness on every theme: CPU for `.zig`, GPU for `.metal`. |
| `make harness THEME=themes/Cygnus_A.zig` | Runs the harness on one theme. |
| `make release` | Builds `dist/Argus-v<VERSION>-macos-arm64.zip` (`VERSION` in the Makefile), with the `.zig` themes precompiled. |
