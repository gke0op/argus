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
//     f32 ~1.2 ms, AMX bf16 688 us, AMX int8 626 us. In a separate study both compensated steps
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
    frame: u64 = 0,

    wf: [N * N]f32, // W, f32 (fallback engine)
    wb: [N * N]u16 align(64), // W, bf16 (AMX engine)
    wq: [N * N]i8 align(64), // W, int8 with one scale per row (AMX int8 engine)
    wscale: [N]f32,
    win: [N]f32,
    bias: [N]f32,
    x: [N * B]f32 align(64), // state, row-major [neuron][instance]
    y: [N * B]f32 align(64),
    y2: [N * 2 * B]f32 align(64), // AMX product of [x_hi | x_lo]
    xp: [N * 2 * B]u16 align(64), // VNNI-packed [x_hi | x_lo]
    disp: [B * N]f32, // display field, [instance][screen column order]
    order: [N]u16, // neuron shown in column k
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
        self.fine_head = 0;
        self.coarse_head = 0;

        var prng = std.Random.DefaultPrng.init(0xA2605);
        const r = prng.random();
        const a: f32 = 0.9 * @sqrt(3.0 / @as(f32, N)); // uniform entries: spectral radius ~0.9
        for (&self.wf, &self.wb) |*x, *hb| {
            x.* = (r.float(f32) * 2 - 1) * a;
            hb.* = bf16(x.*);
        }
        for (0..N) |i| { // int8 rows: scale so the row's largest |w| maps to 127
            var m: f32 = 0;
            for (self.wf[i * N ..][0..N]) |x| m = @max(m, @abs(x));
            self.wscale[i] = m / 127.0;
            for (self.wf[i * N ..][0..N], self.wq[i * N ..][0..N]) |x, *q| q.* = @intFromFloat(@round(x / self.wscale[i]));
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
            const row = self.x[i * B ..][0..B];
            var m: f32 = 0;
            for (row) |v| m += v;
            m /= B;
            var vv: f32 = 0;
            for (row) |v| vv += (v - self.mu[i]) * (v - self.mu[i]);
            self.mu[i] += a * (m - self.mu[i]);
            self.sd[i] = @sqrt(self.sd[i] * self.sd[i] + a * (vv / B - self.sd[i] * self.sd[i])) + 1e-6;
        }
        // display field: smoothed z-scores, transposed to [instance][column]
        for (0..B) |r| for (0..N) |k| {
            const i = self.order[k];
            const z = std.math.clamp((self.x[i * B + r] - self.mu[i]) / (2.5 * self.sd[i]), -1.0, 1.0);
            const d = &self.disp[r * N + k];
            d.* += 0.35 * (z - d.*);
        };
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
        for (0..N) |i| {
            const row = self.y[i * B ..][0..B];
            for (0..B) |c| {
                const u = self.coarse[(self.coarse_head + self.coarse.len - c * ROW_DELAY) % self.coarse.len];
                row[c] += self.win[i] * u + self.bias[i];
            }
        }
        var k: usize = 0;
        while (k < N * B) : (k += 16) self.x[k..][0..16].* = tanhv(self.y[k..][0..16].*);
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
        for (0..N) |k| for (0..B) |c| {
            const v = self.x[k * B + c] * 127.0;
            const hi = @round(v);
            xq[((k / 4) * b2 + c) * 4 + (k % 4)] = @intFromFloat(hi);
            xq[((k / 4) * b2 + B + c) * 4 + (k % 4)] = @intFromFloat(@round((v - hi) * 254.0));
        };
        amxConfig();
        const sa: usize = N;
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
                        : [a0] "r" (&self.wq[i * N + k]), [a1] "r" (&self.wq[(i + 16) * N + k]),
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
            const s = self.wscale[r] / 127.0;
            for (self.y[r * B ..][0..B], acc[r * b2 ..][0..B], acc[r * b2 + B ..][0..B]) |*o, hi, lo|
                o.* = s * (@as(f32, @floatFromInt(hi)) + @as(f32, @floatFromInt(lo)) / 254.0);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const h: usize = @min(self.h, buf.len / stride);
        var mid: [N]f32 = undefined;
        for (0..h) |sy| {
            const f = (@as(f32, @floatFromInt(sy)) + 0.5) * B / @as(f32, @floatFromInt(h)) - 0.5;
            const r0: usize = @intFromFloat(std.math.clamp(@floor(f), 0, B - 1));
            const r1: usize = @min(r0 + 1, B - 1); // usize: @min would narrow to u6
            const wy = std.math.clamp(f - @floor(f), 0, 1);
            for (&mid, self.disp[r0 * N ..][0..N], self.disp[r1 * N ..][0..N]) |*m, a, b| m.* = a + (b - a) * wy;
            const row = buf[sy * stride ..][0..self.w];
            for (row, self.xtap[0..self.w]) |*px, t| {
                const v = mid[t.lo] + (mid[t.hi] - mid[t.lo]) * t.w;
                px.* = self.lut[@intFromFloat(std.math.clamp((v + 1.0) * 127.5, 0.0, 255.0))];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        for (self.x) |v| if (!std.math.isFinite(v)) return true;
        return false;
    }
};

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
