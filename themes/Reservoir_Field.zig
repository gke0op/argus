// @argus-theme: custom_shader
// ============================================================================
// themes/Reservoir_Field.zig: 64 echo state networks, one shared reservoir
//
// What you see: the live activations of a real echo state network. One 1024-neuron reservoir
// (random W, spectral radius ~0.9, tanh units) runs 64 instances at once, one per screen row;
// instance r is driven by a Mackey-Glass chaotic series (tau = 17) delayed by 4r samples, so the
// rows show the reservoir's response to the same signal at 64 moments of its past. Columns are
// the neurons, chained so that neighbours' activation histories correlate best (seriation).
// Colour: each neuron's activation against its own running baseline, in units of its running
// spread (below: blue, at baseline: dark, above: amber), as neuroscience imaging shows dF/F;
// smoothed over a few steps for display only. Raw activations would mostly show the static
// offset each neuron's bias gives it.
//
// Measured / modelled / chosen:
//   * Modelled: the network is the standard ESN update x' = tanh(W x + w_in u + b), run
//     exactly; nothing is faked for the picture. The Mackey-Glass series is integrated online
//     (Euler, dt = 0.1, sampled every 0.5), so it never loops.
//   * Engine (chosen at runtime): on x86 CPUs with AMX, where the kernel grants tile access,
//     W x runs on AMX tiles with the state compensated (x = hi + lo, one fused product over
//     2 x 64 columns): int8 weights and state where the CPU has AMX-INT8, else bf16; elsewhere
//     portable f32 SIMD (AVX-512 / AVX2 / NEON). Measured on a 2-vCPU Emerald Rapids VM, one
//     full step (N = 1024, 64 states, tanh, inputs and display update included; median of 7):
//     f32 1.07 ms, AMX bf16 658 us, AMX int8 385 us (the GEMM itself ~100 us, about half the
//     AMX int8 tile peak; packing, finishing and the display update are vectorized around it). In a separate study both compensated steps
//     forecast Mackey-Glass exactly as well as f32 (NRMSE ratio 1.00; uncompensated: bf16 state
//     1.55x worse, int8 state 3.4x: the cost is in the state, not the low-precision weights).
//   * Same picture everywhere: warm-up and the column order run on the f32 engine, which is
//     bit-identical on x86 and ARM (checked under qemu). The AMX engines round W (bf16, or
//     int8 per row), so they run a very slightly different reservoir: after 600 frames the
//     column order is unchanged and the frame differs from the f32 one by 0.13 levels on
//     average (bf16, max 23) or 0.33 (int8, max 34).
//   * Chosen: palette, display smoothing, the 4-sample row delay, one reservoir step per frame.
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");
const sdk = @import("argus_theme_sdk.zig");

const N = 1024; // neurons
const B = 64; // parallel instances (screen rows)
const ROW_DELAY = 4; // input samples between neighbouring rows
const V16 = @Vector(16, f32);

/// AMX code exists only where it can run: Linux, x86-64, built for a CPU with AMX-BF16.
const amx_built = builtin.os.tag == .linux and builtin.cpu.arch == .x86_64 and
    std.Target.x86.featureSetHas(builtin.cpu.features, .amx_bf16);
const amx_i8_built = amx_built and std.Target.x86.featureSetHas(builtin.cpu.features, .amx_int8);
/// A test driver (the root module) may set `pub const argus_reservoir_force_f32 = true;` to
/// compare engines. (Read the value, not just @hasDecl: a driver declaring it false must not force.)
const force_f32 = if (@hasDecl(@import("root"), "argus_reservoir_force_f32")) @import("root").argus_reservoir_force_f32 else false;
/// Architecture (comptime; a driver may set `pub const argus_reservoir_arch = .leaky;`):
///   dense        uniform random W, spectral radius 0.9 (the shipped picture)
///   leaky        dense W, leak 0.2: x' = 0.8 x + 0.2 tanh(..), a slow integrator
///   chaotic      dense W, spectral radius 1.3: past the edge of chaos
///   cycle_jumps  a ring (x[i] drives x[i+1]) with bidirectional jumps every 7 neurons
///                (Rodan & Tino's cycle reservoir with jumps)
///   small_world  each neuron wired to its 6 nearest ring neighbours, 5% rewired at random
pub const Arch = enum { dense, leaky, chaotic, cycle_jumps, small_world };
const arch: Arch = if (@hasDecl(@import("root"), "argus_reservoir_arch")) @import("root").argus_reservoir_arch else .dense;
const LEAK: f32 = if (arch == .leaky) 0.2 else 1.0;
const force_bf16 = if (@hasDecl(@import("root"), "argus_reservoir_force_bf16")) @import("root").argus_reservoir_force_bf16 else false;

fn bf16(x: f32) u16 { // round to nearest even
    const b: u32 = @bitCast(x);
    return @truncate((b + 0x7FFF + ((b >> 16) & 1)) >> 16);
}
fn fromBf16(h: u16) f32 {
    return @bitCast(@as(u32, h) << 16);
}

inline fn tanhv(x: V16) V16 { // 1 - 2 / (e^2x + 1), e^ via a 2^x polynomial
    const t = @min(@max(x * @as(V16, @splat(2.0 * std.math.log2e)), @as(V16, @splat(-126))), @as(V16, @splat(127)));
    const n = @round(t);
    const r = t - n;
    var p: V16 = @splat(1.5403530e-4);
    inline for (.{ 1.3333558e-3, 9.6181291e-3, 5.5504109e-2, 2.4022651e-1, 6.9314718e-1, 1.0 }) |c| p = p * r + @as(V16, @splat(c));
    const I = @Vector(16, i32);
    const bits: @Vector(16, u32) = @bitCast((@as(I, @intFromFloat(n)) + @as(I, @splat(127))) << @splat(23));
    const e = p * @as(V16, @bitCast(bits));
    return @as(V16, @splat(1)) - @as(V16, @splat(2)) / (e + @as(V16, @splat(1)));
}

const Tap = struct { lo: u16, hi: u16, w: f32 };

pub const State = struct {
    w: usize,
    h: usize,
    engine: enum { f32, amx_bf16, amx_i8 },
    threads: usize, // draw splits rows over this many threads
    frame: u64 = 0,

    wf: [N * N]f32, // W, f32 (fallback engine)
    wb: [N * N]u16 align(64), // W, bf16 (AMX engine)
    wq: [N * N]i8 align(64), // W, int8 with one scale per row, as 16 x 64-byte tiles (AMX int8)
    wscale: [N]f32,
    win: [N]f32,
    bias: [N]f32,
    x: [N * B]f32 align(64), // state, row-major [neuron][instance]
    y: [N * B]f32 align(64),
    y2: [N * 2 * B]f32 align(64), // AMX product of [x_hi | x_lo]
    xp: [N * 2 * B]u16 align(64), // VNNI-packed [x_hi | x_lo]
    disp: [B * N]f32, // display field, [instance][screen column order]
    order: [N]u16, // neuron shown in column k
    rs: [B * 8192]f32 align(64), // disp resampled to screen columns, [instance][screen x]
    mu: [N]f32, // each neuron's running mean and spread (display baseline, ~10 s)
    sd: [N]f32,
    // Mackey-Glass: fine Euler history (lag 170 steps) and the sampled series rows read from
    fine: [256]f64,
    fine_head: usize = 0,
    coarse: [512]f32,
    coarse_head: usize = 0,
    lut: [256]u32,
    xtap: [8192]Tap,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        _ = scale;
        const self = try alloc.create(State);
        self.w = @min(w, self.xtap.len);
        self.h = h;
        self.frame = 0;
        self.threads = std.math.clamp(std.Thread.getCpuCount() catch 1, 1, 8);
        self.fine_head = 0;
        self.coarse_head = 0;

        var prng = std.Random.DefaultPrng.init(0xA2605);
        const r = prng.random();
        const rho: f32 = if (arch == .chaotic) 1.3 else 0.9;
        const a: f32 = rho * @sqrt(3.0 / @as(f32, N)); // uniform entries: spectral radius ~rho
        switch (arch) {
            .dense, .leaky, .chaotic => for (&self.wf) |*x| {
                x.* = (r.float(f32) * 2 - 1) * a;
            },
            .cycle_jumps => {
                @memset(&self.wf, 0);
                for (0..N) |i| self.wf[((i + 1) % N) * N + i] = 1.0; // ring
                var i: usize = 0;
                while (i + 7 < N) : (i += 7) { // jumps, both ways
                    self.wf[i * N + i + 7] = 0.5;
                    self.wf[(i + 7) * N + i] = 0.5;
                }
                scaleToRadius(&self.wf, rho);
            },
            .small_world => {
                @memset(&self.wf, 0);
                for (0..N) |i| for ([_]usize{ 1, 2, 3, N - 1, N - 2, N - 3 }) |d| {
                    const j = if (r.float(f32) < 0.05) r.uintLessThan(usize, N) else (i + d) % N;
                    self.wf[i * N + j] = r.float(f32) * 2 - 1;
                };
                scaleToRadius(&self.wf, rho);
            },
        }
        for (&self.wf, &self.wb) |x, *hb| hb.* = bf16(x);
        for (0..N) |i| { // int8 rows: scale so the row's largest |w| maps to 127
            var m: f32 = 0;
            for (self.wf[i * N ..][0..N]) |x| m = @max(m, @abs(x));
            self.wscale[i] = m / 127.0;
            for (self.wf[i * N ..][0..N], 0..) |x, k| // tile (i/16, k/64), row i%16, byte k%64
                self.wq[((i / 16) * (N / 64) + k / 64) * 1024 + (i % 16) * 64 + k % 64] = @intFromFloat(@round(x / self.wscale[i]));
        }
        for (&self.win, &self.bias) |*x, *b| {
            x.* = (r.float(f32) * 2 - 1) * 0.5; // input scaling: keeps most units out of saturation
            b.* = (r.float(f32) * 2 - 1) * 0.2;
        }
        @memset(&self.x, 0);
        @memset(&self.disp, 0);

        // palette: -1 blue .. 0 near-black .. +1 amber, perceptually eased
        for (&self.lut, 0..) |*px, i| {
            const v = @as(f32, @floatFromInt(i)) / 127.5 - 1.0;
            const m = std.math.pow(f32, @abs(v), 0.8);
            const lo = [3]f32{ 0.012, 0.016, 0.035 };
            const hi = if (v < 0) [3]f32{ 0.10, 0.32, 0.95 } else [3]f32{ 1.0, 0.62, 0.20 };
            var c: [3]u8 = undefined;
            for (0..3) |k| c[k] = @intFromFloat(@round(255.0 * std.math.clamp(lo[k] + (hi[k] - lo[k]) * m, 0.0, 1.0)));
            px.* = sdk.packRGBA(c[0], c[1], c[2]);
        }
        for (0..self.w) |sx| { // screen column -> two neighbouring display columns
            const f = (@as(f32, @floatFromInt(sx)) + 0.5) * N / @as(f32, @floatFromInt(self.w)) - 0.5;
            const lo: usize = @intFromFloat(@max(0, @floor(f)));
            self.xtap[sx] = .{ .lo = @intCast(@min(lo, N - 1)), .hi = @intCast(@min(lo + 1, N - 1)), .w = std.math.clamp(f - @floor(f), 0, 1) };
        }

        for (&self.fine) |*v| v.* = 1.2;
        // Warm-up and column order on the f32 engine (bit-identical on x86 and ARM), so every
        // machine shows the same layout; the faster engine takes over afterwards.
        self.engine = .f32;
        // fill the input history, then let the reservoir forget its zero start
        for (0..self.coarse.len) |_| self.advanceInput();
        for (0..200) |_| {
            self.advanceInput();
            self.reservoirStep();
        }
        self.orderByResponse();
        if (amx_built and !force_f32 and amxEnable())
            self.engine = if (amx_i8_built and !force_bf16) .amx_i8 else .amx_bf16;
        self.resample();
        return self;
    }

    /// Column order (seriation): a greedy chain where each next column is the unvisited neuron
    /// whose activation history correlates best with the current one, over 128 state snapshots
    /// (two moments x 64 instances), so neighbouring columns move together. Uses y2 as scratch
    /// ([sample][neuron]). An earlier angle-in-PCA-plane order was fragile: the reservoir's flat
    /// spectrum left the two components unsettled and the layout near random (neighbouring-column
    /// correlation 0.15).
    fn orderByResponse(self: *State) void {
        const S = 2 * B;
        const data = self.y2[0 .. S * N];
        for (0..2) |m| {
            if (m == 1) for (0..32) |_| {
                self.advanceInput();
                self.reservoirStep();
            };
            for (0..B) |c| for (0..N) |i| {
                data[(m * B + c) * N + i] = self.x[i * B + c];
            };
        }
        var mean: [N]f32 = @splat(0);
        for (0..S) |s| for (0..N) |i| {
            mean[i] += data[s * N + i] / S;
        };
        var nrm: [N]f32 = @splat(0);
        for (0..S) |s| for (0..N) |i| {
            data[s * N + i] -= mean[i];
            nrm[i] += data[s * N + i] * data[s * N + i];
        };
        for (&self.mu, &self.sd, mean, nrm) |*m, *d, mv, v| { // seed the display baseline
            m.* = mv;
            d.* = @sqrt(v / S) + 1e-4;
        }
        for (&nrm) |*v| v.* = 1.0 / (@sqrt(v.*) + 1e-12);
        for (0..S) |s| for (0..N) |i| {
            data[s * N + i] *= nrm[i]; // unit-norm histories: dot product = correlation
        };
        // start at an end of the spectrum: the neuron least like the average history
        var avg: [S]f32 = @splat(0);
        for (0..S) |s| for (0..N) |i| {
            avg[s] += data[s * N + i];
        };
        var cur: usize = 0;
        var lowest: f32 = std.math.inf(f32);
        for (0..N) |i| {
            var c: f32 = 0;
            for (0..S) |s| c += data[s * N + i] * avg[s];
            if (c < lowest) {
                lowest = c;
                cur = i;
            }
        }
        var used: [N]bool = @splat(false);
        var corr: [N]f32 = undefined;
        for (0..N) |k| {
            self.order[k] = @intCast(cur);
            used[cur] = true;
            if (k + 1 == N) break;
            @memset(&corr, 0);
            for (0..S) |s| {
                const c = data[s * N + cur];
                for (&corr, data[s * N ..][0..N]) |*a, d| a.* += c * d;
            }
            var best: usize = 0;
            var best_c: f32 = -std.math.inf(f32);
            for (corr, 0..) |c, j| if (!used[j] and c > best_c) {
                best_c = c;
                best = j;
            };
            cur = best;
        }
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        _ = dt; // one reservoir step per frame: the network's own clock
        self.frame +%= 1;
        self.advanceInput();
        self.reservoirStep();
        // Display baseline: each neuron's running mean and spread over all instances (~10 s), so
        // colour shows its activity against its own baseline (as neuroscience imaging shows
        // dF/F) rather than the static offset its bias gives it.
        const a: f32 = 1.0 / 300.0;
        for (0..N) |i| {
            // 4 x 16 elementwise partials, lanes summed in a fixed order: same on every ISA
            var sm: V16 = @splat(0);
            var sq: V16 = @splat(0);
            const mv: V16 = @splat(self.mu[i]);
            inline for (0..B / 16) |cc| {
                const v: V16 = self.x[i * B + cc * 16 ..][0..16].*;
                sm += v;
                sq += (v - mv) * (v - mv);
            }
            var m: f32 = 0;
            var vv: f32 = 0;
            inline for (0..16) |l| {
                m += sm[l];
                vv += sq[l];
            }
            m /= B;
            self.mu[i] += a * (m - self.mu[i]);
            self.sd[i] = @sqrt(self.sd[i] * self.sd[i] + a * (vv / B - self.sd[i] * self.sd[i])) + 1e-6;
        }
        // display field: smoothed z-scores, transposed to [instance][column] 16 columns at a
        // time (z along each neuron's contiguous row, then across through an L1 tile)
        var zt: [16][B]f32 align(64) = undefined;
        var k: usize = 0;
        while (k < N) : (k += 16) {
            for (0..16) |l| {
                const i = self.order[k + l];
                inline for (0..B / 16) |cc| {
                    const z = (@as(V16, self.x[i * B + cc * 16 ..][0..16].*) - @as(V16, @splat(self.mu[i]))) / @as(V16, @splat(2.5 * self.sd[i]));
                    zt[l][cc * 16 ..][0..16].* = @min(@max(z, @as(V16, @splat(-1.0))), @as(V16, @splat(1.0)));
                }
            }
            for (0..B) |r| {
                var z: V16 = undefined;
                inline for (0..16) |l| z[l] = zt[l][r];
                const d: V16 = self.disp[r * N + k ..][0..16].*;
                self.disp[r * N + k ..][0..16].* = d + @as(V16, @splat(0.35)) * (z - d);
            }
        }
        self.resample();
    }

    /// Horizontal half of the bilinear upscale, once per frame (64 rows): draw then only blends
    /// two contiguous rows per screen row and looks up the colour.
    fn resample(self: *State) void {
        for (0..B) |r| {
            const d = self.disp[r * N ..][0..N];
            for (self.rs[r * self.w ..][0..self.w], self.xtap[0..self.w]) |*o, t| o.* = d[t.lo] + (d[t.hi] - d[t.lo]) * t.w;
        }
    }

    fn advanceInput(self: *State) void {
        // 5 Euler steps of dt = 0.1 per sample: dx/dt = 0.2 x(t-17) / (1 + x(t-17)^10) - 0.1 x
        for (0..5) |_| {
            const cur = self.fine[self.fine_head];
            const lagged = self.fine[(self.fine_head + 256 - 170) % 256];
            self.fine_head = (self.fine_head + 1) % 256;
            self.fine[self.fine_head] = cur + 0.1 * (0.2 * lagged / (1 + std.math.pow(f64, lagged, 10)) - 0.1 * cur);
        }
        self.coarse_head = (self.coarse_head + 1) % self.coarse.len;
        self.coarse[self.coarse_head] = @floatCast(self.fine[self.fine_head] - 0.9);
    }

    fn reservoirStep(self: *State) void {
        switch (self.engine) {
            .f32 => self.productF32(),
            .amx_bf16 => if (amx_built) self.productAmx() else unreachable,
            .amx_i8 => if (amx_i8_built) self.productAmxI8() else unreachable,
        }
        var us: [B]f32 align(64) = undefined; // row c's input sample
        for (&us, 0..) |*u, c| u.* = self.coarse[(self.coarse_head + self.coarse.len - c * ROW_DELAY) % self.coarse.len];
        for (0..N) |i| inline for (0..B / 16) |cc| {
            const k = i * B + cc * 16;
            const v = @as(V16, self.y[k..][0..16].*) + (@as(V16, @splat(self.win[i])) * @as(V16, us[cc * 16 ..][0..16].*) + @as(V16, @splat(self.bias[i])));
            const t = tanhv(v);
            if (LEAK == 1.0) self.x[k..][0..16].* = t else {
                const x0: V16 = self.x[k..][0..16].*;
                self.x[k..][0..16].* = x0 + @as(V16, @splat(LEAK)) * (t - x0);
            }
        };
    }

    /// y = W x, f32, 4 rows x 4 column vectors per register block (B = 64 = 4 vectors).
    fn productF32(self: *State) void {
        var i: usize = 0;
        while (i < N) : (i += 4) {
            var acc: [4][4]V16 = @splat(@splat(@splat(0)));
            for (0..N) |k| {
                var xv: [4]V16 = undefined;
                inline for (0..4) |cc| xv[cc] = self.x[k * B + cc * 16 ..][0..16].*;
                inline for (0..4) |r| {
                    const wv: V16 = @splat(self.wf[(i + r) * N + k]);
                    inline for (0..4) |cc| acc[r][cc] = @mulAdd(V16, wv, xv[cc], acc[r][cc]);
                }
            }
            inline for (0..4) |r| inline for (0..4) |cc| {
                self.y[(i + r) * B + cc * 16 ..][0..16].* = acc[r][cc];
            };
        }
    }

    /// y = W_bf16 (x_hi + x_lo) as one AMX product over 2B columns: bf16 weights cost nothing,
    /// the compensated state keeps f32 accuracy.
    fn productAmx(self: *State) void {
        if (!amx_built) unreachable;
        const b2 = 2 * B;
        for (0..N) |k| for (0..B) |c| {
            const v = self.x[k * B + c];
            const hi = bf16(v);
            self.xp[((k / 2) * b2 + c) * 2 + (k % 2)] = hi;
            self.xp[((k / 2) * b2 + B + c) * 2 + (k % 2)] = bf16(v - fromBf16(hi));
        };
        amxConfig(); // tile config is per thread: set it on whichever thread steps us
        const sa: usize = N * 2;
        const sb: usize = b2 * 4;
        var i: usize = 0;
        while (i < N) : (i += 32) {
            var j: usize = 0;
            while (j < b2) : (j += 32) {
                asm volatile ("tilezero %%tmm0\ntilezero %%tmm1\ntilezero %%tmm2\ntilezero %%tmm3" ::: .{ .memory = true });
                var k: usize = 0;
                while (k < N) : (k += 32) {
                    asm volatile (
                        \\tileloadd (%[a0], %[sa]), %%tmm4
                        \\tileloadd (%[a1], %[sa]), %%tmm5
                        \\tileloadd (%[b0], %[sb]), %%tmm6
                        \\tileloadd (%[b1], %[sb]), %%tmm7
                        \\tdpbf16ps %%tmm6, %%tmm4, %%tmm0
                        \\tdpbf16ps %%tmm7, %%tmm4, %%tmm1
                        \\tdpbf16ps %%tmm6, %%tmm5, %%tmm2
                        \\tdpbf16ps %%tmm7, %%tmm5, %%tmm3
                        :
                        : [a0] "r" (&self.wb[i * N + k]), [a1] "r" (&self.wb[(i + 16) * N + k]),
                          [b0] "r" (&self.xp[((k / 2) * b2 + j) * 2]), [b1] "r" (&self.xp[((k / 2) * b2 + j + 16) * 2]),
                          [sa] "r" (sa), [sb] "r" (sb),
                        : .{ .memory = true });
                }
                asm volatile (
                    \\tilestored %%tmm0, (%[c0], %[s])
                    \\tilestored %%tmm1, (%[c1], %[s])
                    \\tilestored %%tmm2, (%[c2], %[s])
                    \\tilestored %%tmm3, (%[c3], %[s])
                    :
                    : [c0] "r" (&self.y2[i * b2 + j]), [c1] "r" (&self.y2[i * b2 + j + 16]),
                      [c2] "r" (&self.y2[(i + 16) * b2 + j]), [c3] "r" (&self.y2[(i + 16) * b2 + j + 16]), [s] "r" (sb),
                    : .{ .memory = true });
            }
        }
        asm volatile ("tilerelease" ::: .{ .memory = true });
        for (0..N) |r| {
            const hi = self.y2[r * b2 ..][0..B];
            const lo = self.y2[r * b2 + B ..][0..B];
            for (self.y[r * B ..][0..B], hi, lo) |*o, a, b| o.* = a + b;
        }
    }

    /// y = diag(s) W_q (x_hi + x_lo / 254), with x * 127 = x_hi + x_lo / 254 (both int8; |x| <= 1
    /// after tanh), as one AMX int8 product over 2B columns. Exact integer sums; reuses xp and y2.
    fn productAmxI8(self: *State) void {
        if (!amx_i8_built) unreachable;
        const b2 = 2 * B;
        const xq: []i8 = @as([*]i8, @ptrCast(&self.xp))[0 .. N * b2];
        const acc: []i32 = @as([*]i32, @ptrCast(&self.y2))[0 .. N * b2];
        const I16 = @Vector(16, i8);
        const quads = comptime blk: { // byte 4c + q <- row q, column c (a 4 x 16 transpose)
            var m: [64]i32 = undefined;
            for (0..16) |c| for (0..4) |q| {
                m[4 * c + q] = q * 16 + c;
            };
            break :blk m;
        };
        var k4: usize = 0;
        while (k4 < N) : (k4 += 4) {
            inline for (0..B / 16) |cc| {
                var hi: [4]I16 = undefined;
                var lo: [4]I16 = undefined;
                inline for (0..4) |q| {
                    const v = @as(V16, self.x[(k4 + q) * B + cc * 16 ..][0..16].*) * @as(V16, @splat(127.0));
                    const h = @round(v);
                    hi[q] = @intFromFloat(h);
                    lo[q] = @intFromFloat(@round((v - h) * @as(V16, @splat(254.0))));
                }
                xq[((k4 / 4) * b2 + cc * 16) * 4 ..][0..64].* = @shuffle(i8, @as(@Vector(64, i8), @bitCast(hi)), undefined, quads);
                xq[((k4 / 4) * b2 + B + cc * 16) * 4 ..][0..64].* = @shuffle(i8, @as(@Vector(64, i8), @bitCast(lo)), undefined, quads);
            }
        }
        amxConfig();
        const sa: usize = 64; // contiguous 1 KB weight tiles
        const sb: usize = b2 * 4;
        var i: usize = 0;
        while (i < N) : (i += 32) {
            var j: usize = 0;
            while (j < b2) : (j += 32) {
                asm volatile ("tilezero %%tmm0\ntilezero %%tmm1\ntilezero %%tmm2\ntilezero %%tmm3" ::: .{ .memory = true });
                var k: usize = 0;
                while (k < N) : (k += 64) {
                    asm volatile (
                        \\tileloadd (%[a0], %[sa]), %%tmm4
                        \\tileloadd (%[a1], %[sa]), %%tmm5
                        \\tileloadd (%[b0], %[sb]), %%tmm6
                        \\tileloadd (%[b1], %[sb]), %%tmm7
                        \\tdpbssd %%tmm6, %%tmm4, %%tmm0
                        \\tdpbssd %%tmm7, %%tmm4, %%tmm1
                        \\tdpbssd %%tmm6, %%tmm5, %%tmm2
                        \\tdpbssd %%tmm7, %%tmm5, %%tmm3
                        :
                        : [a0] "r" (&self.wq[((i / 16) * (N / 64) + k / 64) * 1024]), [a1] "r" (&self.wq[((i / 16 + 1) * (N / 64) + k / 64) * 1024]),
                          [b0] "r" (&xq[((k / 4) * b2 + j) * 4]), [b1] "r" (&xq[((k / 4) * b2 + j + 16) * 4]),
                          [sa] "r" (sa), [sb] "r" (sb),
                        : .{ .memory = true });
                }
                asm volatile (
                    \\tilestored %%tmm0, (%[c0], %[s])
                    \\tilestored %%tmm1, (%[c1], %[s])
                    \\tilestored %%tmm2, (%[c2], %[s])
                    \\tilestored %%tmm3, (%[c3], %[s])
                    :
                    : [c0] "r" (&acc[i * b2 + j]), [c1] "r" (&acc[i * b2 + j + 16]),
                      [c2] "r" (&acc[(i + 16) * b2 + j]), [c3] "r" (&acc[(i + 16) * b2 + j + 16]), [s] "r" (sb),
                    : .{ .memory = true });
            }
        }
        asm volatile ("tilerelease" ::: .{ .memory = true });
        for (0..N) |r| {
            const s: V16 = @splat(self.wscale[r] / 127.0);
            inline for (0..B / 16) |cc| {
                const hi: V16 = @floatFromInt(@as(@Vector(16, i32), acc[r * b2 + cc * 16 ..][0..16].*));
                const lo: V16 = @floatFromInt(@as(@Vector(16, i32), acc[r * b2 + B + cc * 16 ..][0..16].*));
                self.y[r * B + cc * 16 ..][0..16].* = s * (hi + lo / @as(V16, @splat(254.0)));
            }
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        self.drawLut(buf, stride, &self.lut);
    }

    /// Rows split over `threads` (spawned per call, as argus_kernel.zig does: ~0.1 ms each).
    fn drawLut(self: *const State, buf: []u32, stride: usize, lut: *const [256]u32) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const h: usize = @min(self.h, buf.len / stride);
        var pool: [8]?std.Thread = @splat(null);
        for (1..self.threads) |t| pool[t] = std.Thread.spawn(.{}, drawRows, .{ self, buf, stride, lut, h, h * t / self.threads, h * (t + 1) / self.threads }) catch null;
        drawRows(self, buf, stride, lut, h, 0, h / self.threads);
        for (pool[1..self.threads], 1..) |th, t| if (th) |x| x.join() else drawRows(self, buf, stride, lut, h, h * t / self.threads, h * (t + 1) / self.threads);
    }

    fn drawRows(self: *const State, buf: []u32, stride: usize, lut: *const [256]u32, h: usize, y0: usize, y1: usize) void {
        for (y0..y1) |sy| {
            const f = (@as(f32, @floatFromInt(sy)) + 0.5) * B / @as(f32, @floatFromInt(h)) - 0.5;
            const r0: usize = @intFromFloat(std.math.clamp(@floor(f), 0, B - 1));
            const r1: usize = @min(r0 + 1, B - 1); // usize: @min would narrow to u6
            const wy = std.math.clamp(f - @floor(f), 0, 1);
            const row = buf[sy * stride ..][0..self.w];
            const ra = self.rs[r0 * self.w ..][0..self.w];
            const rb = self.rs[r1 * self.w ..][0..self.w];
            var x: usize = 0;
            while (x + 16 <= self.w) : (x += 16) { // 16 pixels: blend and index as vectors
                const va: V16 = ra[x..][0..16].*;
                const v = va + (@as(V16, rb[x..][0..16].*) - va) * @as(V16, @splat(wy));
                const fi = @min(@max((v + @as(V16, @splat(1.0))) * @as(V16, @splat(127.5)), @as(V16, @splat(0))), @as(V16, @splat(255)));
                const idx: @Vector(16, u32) = @intFromFloat(fi);
                var out: @Vector(16, u32) = undefined;
                inline for (0..16) |l| out[l] = lut[idx[l]];
                row[x..][0..16].* = out;
            }
            for (row[x..], ra[x..], rb[x..]) |*px, a, b| {
                const v = a + (b - a) * wy;
                px.* = lut[@intFromFloat(std.math.clamp((v + 1.0) * 127.5, 0.0, 255.0))];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        for (self.x) |v| if (!std.math.isFinite(v)) return true;
        return false;
    }
};

/// Draw straight into a host's display memory in its channel order (the Linux host hands over
/// X11's BGRX), skipping its reorder pass; same layout as cage.Target / argus_kernel.Target.
const Target = extern struct { px: [*]u32, len: usize, stride: usize, shift: [3]u8 };
pub export fn argus_theme_draw_target(raw: ?*anyopaque, t: *const Target) callconv(.c) void {
    const self: *const State = @ptrCast(@alignCast(raw orelse return));
    for (t.shift) |sh| if (sh > 24) return;
    var lut: [256]u32 = undefined;
    for (&lut, self.lut) |*o, c| { // [R, G, B, A] bytes -> the target's bit offsets
        o.* = 0;
        inline for (0..3) |ch| o.* |= ((c >> (8 * ch)) & 0xFF) << @intCast(t.shift[ch]);
    }
    self.drawLut(t.px[0..t.len], t.stride, &lut);
}

/// Scale W to spectral radius `rho`, estimated by Gelfand's formula (geometric mean growth of
/// ||W^k v|| over 200 steps after 100 of burn-in); deterministic f32, the same on every machine.
fn scaleToRadius(w: *[N * N]f32, rho: f32) void {
    var v: [N]f32 = undefined;
    var u: [N]f32 = undefined;
    for (&v, 0..) |*e, i| e.* = @floatFromInt((i * 2654435761) % 1000 + 1);
    var log_sum: f64 = 0;
    for (0..300) |it| {
        for (&u, 0..) |*o, i| {
            var acc: f32 = 0;
            for (w[i * N ..][0..N], v) |a, b| acc += a * b;
            o.* = acc;
        }
        var nrm: f32 = 0;
        for (u) |e| nrm += e * e;
        nrm = @sqrt(nrm);
        if (nrm == 0) return;
        if (it >= 100) log_sum += @log(@as(f64, nrm));
        for (&v, u) |*e, o| e.* = o / nrm;
    }
    const est: f32 = @floatCast(@exp(log_sum / 200));
    for (w) |*e| e.* *= rho / est;
}

fn amxEnable() bool {
    if (!amx_built) return false;
    const linux = std.os.linux; // ARCH_REQ_XCOMP_PERM for XFEATURE_XTILEDATA
    return linux.errno(linux.syscall2(.arch_prctl, 0x1023, 18)) == .SUCCESS;
}

fn amxConfig() void {
    if (!amx_built) return;
    const Cfg = extern struct { palette: u8 = 1, start_row: u8 = 0, reserved: [14]u8 = @splat(0), colsb: [16]u16 = @splat(0), rows: [16]u8 = @splat(0) };
    var cfg = Cfg{};
    for (0..8) |t| {
        cfg.rows[t] = 16;
        cfg.colsb[t] = 64;
    }
    asm volatile ("ldtilecfg (%[c])" : : [c] "r" (&cfg) : .{ .memory = true });
}

comptime {
    sdk.exportTheme(State);
}
