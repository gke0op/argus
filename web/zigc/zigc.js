// web/zigc/zigc.js — compile an Argus Zig theme with zig.wasm (Zig 0.17.0), in a Worker or Node.
//
// Two runs of the real compiler, as `make web-wasm` does natively:
//   1. Gate 1, type-checked for a 64-bit target: `build-obj -fno-emit-bin -target
//      wasm64-freestanding THEME`. Natively this is `-target aarch64-macos`; zig.wasm (built with
//      -Ddev=wasm) has no aarch64 or LLVM backend, and Sema asks the backend about every
//      callconv(.c) function, so it cannot type-check for aarch64 at all. wasm64 has the same
//      64-bit usize, so `const x: u32 = n_usize;` fails here with the native error, at the same
//      file:line:col. What differs is the OS: code that needs macOS or libc (std.Thread,
//      std.fs, std.c) is checked against freestanding here.
//   2. The module: `build-exe -target wasm32-freestanding -mcpu=generic -fsingle-threaded` with
//      the self-hosted wasm backend (-fno-llvm -fno-lld), web/wasm/runtime.zig and
//      src/harness_gates.zig as in `make web-wasm`. No SIMD and no threads, unlike `make
//      web-wasm`: in Zig 0.17.0 the self-hosted backend's +simd128 output does not validate (a
//      function returning a @Vector: "type error in branch, expected v128, got i32"), its
//      threaded output does not either (an invalid atomic opcode in compiler_rt), and its inline
//      assembler has no global.get/global.set for the Workers' stacks. Vectors are lowered to
//      scalar code, which gives the same values.
//
// The virtual cwd ('.'):
//   theme/NAME.zig, theme/argus_theme_sdk.zig, theme/argus_kernel.zig   the theme and what it imports
//   web/wasm/runtime.zig, web/wasm/wasm_heap.zig, src/harness_gates.zig, web/zigc/root.zig
//   web/zigc/absent.zig                                                   written here (see root.zig)
//   out/NAME.st.wasm                                                      the result

import { runWasi } from './wasi.js';

/// Files the compile needs besides the theme: [path in the virtual cwd, path in the repo].
export const SUPPORT = [
  ['theme/argus_theme_sdk.zig', 'themes/argus_theme_sdk.zig'],
  ['theme/argus_kernel.zig', 'themes/cpu/argus_kernel.zig'],
  ['web/wasm/runtime.zig', 'web/wasm/runtime.zig'],
  ['web/wasm/wasm_heap.zig', 'web/wasm/wasm_heap.zig'],
  ['web/zigc/root.zig', 'web/zigc/root.zig'],
  ['src/harness_gates.zig', 'src/harness_gates.zig'],
];

/// The theme functions runtime.zig takes as weak (optional) for a hand-written C-ABI theme.
const OPTIONAL = ['argus_theme_init', 'argus_theme_deinit', 'argus_theme_step', 'argus_theme_draw', 'argus_theme_allocs_init',
  'argus_theme_allocs_after_init', 'argus_theme_bytes_live', 'argus_theme_has_nan', 'argus_render_theme'];

const COMMON = ['-fno-llvm', '-fno-lld', '-O', 'ReleaseFast', '--color', 'off'];

export function semaArgs(name) {
  return ['zig', 'build-obj', '-fno-emit-bin', ...COMMON, '-target', 'wasm64-freestanding', '-mcpu=generic+simd128', `theme/${name}.zig`];
}

export function buildArgs(name) {
  return ['zig', 'build-exe', ...COMMON, '-target', 'wasm32-freestanding', '-mcpu=generic', '-fsingle-threaded',
    '-fno-compiler-rt', '-fno-entry', '-rdynamic', ...(globalThis.process?.env?.ZIGC_NOSTRIP ? [] : ['-fstrip']),
    '--import-memory', '--initial-memory=4194304', '--max-memory=1073741824',
    '--dep', 'runtime', '--dep', 'compiler_rt', '--dep', 'absent', '-Mroot=web/zigc/root.zig',
    '--dep', 'theme', '--dep', 'harness_gates', '-Mruntime=web/wasm/runtime.zig',
    `-Mtheme=theme/${name}.zig`, '-Mharness_gates=src/harness_gates.zig',
    '-Mabsent=web/zigc/absent.zig', '-fno-builtin', '-Mcompiler_rt=/lib/compiler_rt.zig',
    `-femit-bin=out/${name}.st.wasm`];
}

/// A theme file name the build accepts: letters, digits and _ (it becomes a module path).
export function themeName(fileName) {
  const n = String(fileName || '').replace(/^.*[\\/]/, '').replace(/\.zig$/i, '').replace(/[^A-Za-z0-9_]/g, '_');
  return /^[A-Za-z_]/.test(n) ? n : `T_${n || 'Theme'}`;
}

/// Compile `source` as theme NAME on `fs` (a MemFS with /lib mounted and SUPPORT written).
/// onPhase(p): 'sema' | 'build'. Returns { ok, gate1: { ok, log, ms }, build: { ok, log, ms },
/// wasm (Uint8Array) or null, args }.
export function compileTheme(zigModule, fs, name, source, { onPhase, onLog } = {}) {
  // Each theme gets a clean theme/NAME.zig; the out/ folder is emptied so a failed build
  // never hands back an earlier module.
  fs.writeFile(fs.cwd, `theme/${name}.zig`, source);
  const out = fs.mkdirp(fs.cwd, 'out');
  out.children.clear();
  const run = (args) => runWasi(zigModule, { args, fs, onStderr: onLog });

  onPhase?.('sema');
  const s = run(semaArgs(name));
  const gate1 = { ok: s.code === 0, log: s.stderr.trim(), ms: s.ms, args: semaArgs(name) };
  if (!gate1.ok) return { ok: false, gate1, build: null, wasm: null };

  // The optional ABI functions the theme lacks: link with none listed; for each the linker
  // reports undefined, list it and link again (what dlsym's null is natively).
  onPhase?.('build');
  const absent = [];
  let b;
  for (let pass = 0; pass < 3; pass++) {
    fs.writeFile(fs.cwd, 'web/zigc/absent.zig', `pub const names = [_][]const u8{${absent.map((a) => ` "${a}",`).join('')} };\n`);
    b = run(buildArgs(name));
    const missing = [...b.stderr.matchAll(/undefined function: (argus_[a-z_]+)/g)].map((m) => m[1]).filter((m) => OPTIONAL.includes(m) && !absent.includes(m));
    if (b.code === 0 || !missing.length) break;
    absent.push(...missing);
  }
  const wasm = b.code === 0 ? fs.readFile(fs.cwd, `out/${name}.st.wasm`) : null;
  const build = { ok: b.code === 0 && !!wasm && wasm.length > 8, log: b.stderr.trim(), ms: b.ms, args: buildArgs(name), absent };
  return { ok: build.ok, gate1, build, wasm: build.ok ? wasm.slice() : null };
}

/// Zig's diagnostics as [{ file, line, col, kind, msg }] (for links and highlighting).
export function parseDiagnostics(log) {
  const out = [];
  for (const m of String(log).matchAll(/^(.+?):(\d+):(\d+): (error|note): (.*)$/gm)) {
    out.push({ file: m[1], line: Number(m[2]), col: Number(m[3]), kind: m[4], msg: m[5] });
  }
  return out;
}
