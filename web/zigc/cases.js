// web/zigc/cases.js — the inputs the in-page compiler must survive (web/zigc/test.mjs, verify.html).
//
// Each case is a source made from tests/fixtures/Gate0_Control.zig (a passing theme) or from
// nothing, with what the page must end with: a verdict (a gate that fails, or PASS), or a clear
// message of a kind ('compile-error', 'compiler-crash', 'compiler-timeout', 'not-zig'), in
// bounded time. After every one of them, the next ordinary compile must work.

const INIT_ANCHOR = 'st.* = .{ .w = w, .h = h, .t = 0, .centre = 0.2 };';
const STEP_ANCHOR = 'st.t += dt;';

/// A deterministic byte stream (xorshift32), for "binary garbage".
function garbage(n, seed = 0x9e3779b9) {
  const b = new Uint8Array(n);
  let x = seed >>> 0;
  for (let i = 0; i < n; i++) { x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; b[i] = x & 0xff; }
  return b;
}

/// [name, source (string or Uint8Array), expect, limitS, flags] for every case. expect: { gate: N } (that gate
/// fails, the others as the theme deserves), { pass: true }, or { kind: '...' } (a message, no
/// verdict). `limitS`: the most this case may take, end to end.
export function pathologicalCases(gate0) {
  const at = (anchor, code) => {
    if (!gate0.includes(anchor)) throw new Error(`Gate0_Control.zig no longer contains ${anchor}`);
    return gate0.replace(anchor, `${anchor}\n${code}`);
  };
  // ~500 KB of real Zig: thousands of small unused functions (AstGen parses every one).
  let big = gate0 + '\n';
  for (let i = 0; big.length < 500 * 1024; i++) big += `fn unused_${i}(x: u32) u32 {\n    const y = x *% ${i + 1} +% ${(i * 2654435761) >>> 0};\n    return y ^ (y >> 7);\n}\n`;
  return [
    // Comptime recursion that never ends. Native Zig stops it at its branch quota (Gate 1 FAIL);
    // zig.wasm runs on the browser's far smaller stack and overflows first: a clear message.
    ['Path_ComptimeRecursion', at(INIT_ANCHOR, '    _ = comptime forever(0);') + '\nfn forever(comptime n: u64) u64 {\n    return forever(n + 1);\n}\n', { kind: ['compiler-crash'] }, 60],
    // A comptime table far past what the compiler can hold in a reasonable time: the page's
    // 60 s compile limit stops it, or Zig runs out of memory (either: a clear message).
    ['Path_HugeComptimeTable', at(INIT_ANCHOR, '    std.mem.doNotOptimizeAway(&huge_table);') + '\nconst huge_table = blk: {\n    @setEvalBranchQuota(4_000_000_000);\n    var a: [1 << 26]u32 = undefined;\n    for (&a, 0..) |*x, i| x.* = @truncate(i *% 2654435761);\n    break :blk a;\n};\n', { kind: ['compiler-timeout', 'compiler-crash'] }, 75],
    // A comptime loop that runs for minutes in little memory: the page's 60 s compile limit stops
    // it (browser only: the Node test has no such limit).
    ['Path_ComptimeSpin', at(INIT_ANCHOR, '    std.mem.doNotOptimizeAway(spin_sum);') + '\nconst spin_sum = blk: {\n    @setEvalBranchQuota(4_000_000_000);\n    var x: u32 = 0;\n    var i: u32 = 0;\n    while (i < 3_000_000_000) : (i += 1) x +%= i;\n    break :blk x;\n};\n', { kind: ['compiler-timeout'] }, 75, { browserOnly: true }],
    // Parser recursion deep enough to overflow zig.wasm's stack.
    ['Path_DeepNesting', at(INIT_ANCHOR, `    const deep: u32 = ${'('.repeat(200000)}1${')'.repeat(200000)};\n    _ = deep;`), { kind: ['compiler-crash'] }, 60],
    // Runtime: never returns from init, then from step (Gate 3: the 10 s watchdog).
    ['Path_InitLoop', at(INIT_ANCHOR, '    var spin: u32 = 0;\n    while (true) spin +%= 1;'), { gate: 3 }, 40],
    ['Path_StepLoop', at(STEP_ANCHOR, '    var spin: u32 = 0;\n    while (true) spin +%= 1;'), { gate: 3 }, 40],
    // Allocates 1 MiB at a time until the 1 GiB wasm memory is gone, then panics.
    ['Path_AllocStorm', at(INIT_ANCHOR, '    while (true) {\n        const p = std.heap.page_allocator.alloc(u8, 1 << 20) catch @panic("out of memory");\n        p[0] = 1;\n    }'), { gate: 3 }, 60],
    // 500 KB of source: compiles and passes.
    ['Path_BigSource', big, { pass: true }, 60],
    // 64 KB of random bytes named .zig: Zig's own parse error (Gate 1).
    ['Path_Garbage', garbage(64 * 1024), { gate: 1 }, 30],
  ];
}
