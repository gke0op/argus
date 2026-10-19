// BELOUSOV-ZHABOTINSKY DISH // themes/Opus55_Field.zig
// Claude Opus 5.5 (agentic ARGUS-BENCH run, Track B), 2026-10-19.
//
// What you see: a thin layer of ferroin-catalysed BZ solution on a light box, seen from
// above. Blue bands are oxidised catalyst (ferriin) sweeping through red-orange reduced
// ferroin as rotating spiral waves; where two waves meet they annihilate along a seam.
// Every spiral turns once in about 15 s; fronts creep a few pixels a second.
//
// Sources: none fetched this session; the facts below are from memory and are tagged so.
//   - BZ waves in a ferroin dish are blue (oxidised) fronts in a red (reduced) medium
//     [memory] -> the colour map runs between those two states only.
//   - The two-variable Oregonator (Tyson & Fife 1980; Jahnke & Winfree's parameters
//     eps=0.05, f=1.4, q=0.002) is the standard reduced model of the reaction [memory]
//     -> it is what step() integrates.
//   - Broken wave fronts curl into spirals; colliding fronts annihilate [memory, and
//     visible in the output].
//   - Heterogeneous sites (dust, bubbles) act as pacemakers emitting target rings [memory]
//     -> two pacemakers fire every 9 model time units if their site has recovered.
// COMPUTED: u (HBrO2, the autocatalyst) and v (oxidised catalyst) on a 481x301 periodic
//   grid at 1920x1200; spiral period measured at 2.82-2.89 model time units over 17,000
//   substeps; v peaks at 0.245. Colour is Beer-Lambert transmission of the light box
//   through a mixture of the two catalyst states, by fraction oxidised.
// CHOSEN: grid scale (h = 0.33 model units per 2 points); time-lapse (0.19 model units per
//   screen second, so a spiral period is ~15 s on screen; real dishes run 30-60 s
//   [memory]); the RGB absorbances (rough, not from spectra: the oxidised state is made
//   bluer than ferriin's weak 590 nm band would give, to match the look of photos);
//   v = 0.2 as "fully oxidised" with a smoothstep from 30% to 90% of that; the light
//   box's brightness and falloff; five seeded spirals and their positions; pacemakers.
// NOT MODELLED: catalyst diffusion (Dv = 0, as for a gel-immobilised catalyst); CO2
//   bubbles; the dish rim and meniscus; slow ageing of the reaction (a real dish runs
//   down in an hour or so; this one runs forever); spiral tip meander beyond what the
//   model gives at these parameters.
// CHECKED: harness gates (PASS). The period and v range above come from a throwaway
//   debug driver (deleted). Not checked: behaviour beyond ~140 model time units
//   (~12 min of screen time); periodic wrap keeps every spiral, and pacemakers re-seed
//   waves if the field ever goes quiet, but that is reasoned, not run for hours.
// How it works: init() seeds spiral phase around five cores and runs 5,000 substeps
//   (~30 model time units) so the first frame already shows developed spirals; this
//   makes init take roughly a second (estimated, not timed). step() runs explicit-Euler
//   substeps (dt = 0.006, 8-wide SIMD, the stiff f-term implicit in u) at a rate set by
//   dt, then maps v to colour per cell. draw() upsamples cell colours bilinearly with
//   16-bit-lane SWAR arithmetic.
// Cost: harness 2.3 ms/frame at 1920x1200 on a shared machine. In the harness (dt =
//   0.008) only one frame in four runs a substep; live at 30 FPS each frame runs about
//   one substep (~0.2 ms more, estimated).

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

// Model grid: one cell per CELL_PT screen points.
const CELL_PT: f64 = 2.0;
const MAX_GW: usize = 1920 / 2 + 2;
const MAX_GH: usize = 1200 / 2 + 2;
const MAX_CELLS: usize = MAX_GW * MAX_GH;

// Two-variable Oregonator (Tyson & Fife 1980):
//   du/dt = (u - u^2 - f v (u - q)/(u + q)) / eps + Du lap(u)
//       dv/dt = u - v
const EPS: f32 = 0.05;
const F: f32 = 1.4;
const Q: f32 = 0.002;
const DU: f32 = 1.0;
const H: f32 = 0.33; // model length units per cell
const SDT: f32 = 0.006; // substep: diffusion limit h^2/4 = 0.027; stiff f-term implicit

const SIM_RATE: f64 = 0.19; // model time units per screen second (CHOSEN)
const MAX_SUB: usize = 24;
const WARM_SUB: usize = 5000;

const VMAX: f32 = 0.20; // v giving fully oxidised catalyst in the colour map (CHOSEN)

const N_PM: usize = 2;
const PM_PERIOD: f32 = 9.0; // model time units between pacemaker firings

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    acc: f64,
    sim_t: f32,
    pm_next: f32,

    gw: usize,
    gh: usize,
    cell_px: f64,
    cur: usize,

    u: [2][MAX_CELLS]f32,
    v: [2][MAX_CELLS]f32,
    vig: [MAX_CELLS]f32,
    col: [MAX_CELLS]u64, // SWAR colour: r | g<<16 | b<<32
    lut: [256]u64,

    xi: [MAX_W]u32,
    xt: [MAX_W]u32,
    yi: [MAX_H]u32,
    yt: [MAX_H]u32,

    pm_x: [N_PM]usize,
    pm_y: [N_PM]usize,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(@max(w, 1), MAX_W);
        self.h = @min(@max(h, 1), MAX_H);
        self.scale = if (scale > 0.0) scale else 1.0;
        self.time_sec = 0.0;
        self.acc = 0.0;
        self.sim_t = 0.0;
        self.pm_next = 4.0;
        self.cur = 0;

        self.cell_px = @max(1.0, CELL_PT * self.scale);
        const fw: f64 = @floatFromInt(self.w);
        const fh: f64 = @floatFromInt(self.h);
        self.gw = @min(MAX_GW, @as(usize, @intFromFloat(@floor((fw - 1.0) / self.cell_px))) + 2);
        self.gh = @min(MAX_GH, @as(usize, @intFromFloat(@floor((fh - 1.0) / self.cell_px))) + 2);

        // Bilinear upsampling tables.
        for (0..self.w) |x| {
            const g = @as(f64, @floatFromInt(x)) / self.cell_px;
            const gi: usize = @min(self.gw - 2, @as(usize, @intFromFloat(@floor(g))));
            self.xi[x] = @intCast(gi);
            self.xt[x] = @intFromFloat(@min(256.0, @max(0.0, (g - @as(f64, @floatFromInt(gi))) * 256.0)));
        }
        for (0..self.h) |y| {
            const g = @as(f64, @floatFromInt(y)) / self.cell_px;
            const gi: usize = @min(self.gh - 2, @as(usize, @intFromFloat(@floor(g))));
            self.yi[y] = @intCast(gi);
            self.yt[y] = @intFromFloat(@min(256.0, @max(0.0, (g - @as(f64, @floatFromInt(gi))) * 256.0)));
        }

        self.buildLut();

        // Light-box falloff (cells).
        const gwf: f32 = @floatFromInt(self.gw);
        const ghf: f32 = @floatFromInt(self.gh);
        for (0..self.gh) |j| {
            for (0..self.gw) |i| {
                const nx = (@as(f32, @floatFromInt(i)) / gwf - 0.5) * 2.0;
                const ny = (@as(f32, @floatFromInt(j)) / ghf - 0.5) * 2.0 * (ghf / gwf);
                const r2 = nx * nx + ny * ny;
                self.vig[j * self.gw + i] = @max(0.0, 1.0 - 0.45 * r2);
            }
        }

        self.seed();
        self.pm_x = .{ self.gw * 3 / 4, self.gw / 5 };
        self.pm_y = .{ self.gh / 4, self.gh * 3 / 4 };

        for (0..WARM_SUB) |_| self.substep();
        self.colorize();
        return self;
    }

    fn buildLut(self: *State) void {
        // Beer-Lambert transmission of a light box through the dish. Rough RGB absorbances of
        // reduced ferroin (red-orange) and oxidised ferriin (pale blue), peak absorbance CHOSEN.
        const a_red = [3]f32{ 0.04, 0.62, 0.95 };
        const a_ox = [3]f32{ 0.55, 0.22, 0.04 };
        const peak: f32 = 1.9;
        const lamp = [3]f32{ 0.62, 0.60, 0.55 };
        for (0..256) |k| {
            const x: f32 = @as(f32, @floatFromInt(k)) / 255.0;
            const tt = math.clamp((x - 0.3) / 0.6, 0.0, 1.0);
            const ox = tt * tt * (3.0 - 2.0 * tt);
            var lanes: [3]u64 = undefined;
            for (0..3) |c| {
                const a = peak * ((1.0 - ox) * a_red[c] + ox * a_ox[c] * 1.0);
                const lin = lamp[c] * math.pow(f32, 10.0, -a);
                const srgb = math.pow(f32, @max(0.0, lin), 1.0 / 2.2);
                lanes[c] = @intFromFloat(@min(255.0, @max(0.0, srgb * 255.0 + 0.5)));
            }
            self.lut[k] = lanes[0] | (lanes[1] << 16) | (lanes[2] << 32);
        }
    }

    fn seed(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const K: usize = 5;
        var cx: [K]f32 = undefined;
        var cy: [K]f32 = undefined;
        var ch: [K]f32 = undefined;
        var rng: u64 = 0x9E3779B97F4A7C15;
        for (0..K) |k| {
            rng = rng *% 6364136223846793005 +% 1442695040888963407;
            const a: f32 = @floatFromInt(@as(u32, @truncate(rng >> 40)) % 1000);
            rng = rng *% 6364136223846793005 +% 1442695040888963407;
            const b: f32 = @floatFromInt(@as(u32, @truncate(rng >> 40)) % 1000);
            cx[k] = (0.1 + 0.8 * a / 1000.0) * @as(f32, @floatFromInt(gw));
            cy[k] = (0.1 + 0.8 * b / 1000.0) * @as(f32, @floatFromInt(gh));
            ch[k] = if (k % 2 == 0) 1.0 else -1.0;
        }
        const lam: f32 = 100.0; // initial winding pitch in cells
        for (0..gh) |j| {
            for (0..gw) |i| {
                const fx: f32 = @floatFromInt(i);
                const fy: f32 = @floatFromInt(j);
                var best: usize = 0;
                var bd: f32 = 1e30;
                for (0..K) |k| {
                    const dx = fx - cx[k];
                    const dy = fy - cy[k];
                    const d = dx * dx + dy * dy;
                    if (d < bd) {
                        bd = d;
                        best = k;
                    }
                }
                const dx = fx - cx[best];
                const dy = fy - cy[best];
                const ang = ch[best] * math.atan2(dy, dx) / (2.0 * math.pi);
                const ph = ang + @sqrt(bd) / lam;
                const s = ph - @floor(ph);
                const idx = j * gw + i;
                if (s < 0.06) {
                    self.u[0][idx] = 0.9;
                    self.v[0][idx] = 0.05;
                } else {
                    self.u[0][idx] = Q;
                    self.v[0][idx] = 0.25 * (1.0 - (s - 0.06) / 0.94);
                }
            }
        }
    }

    const VL = 8;
    const V = @Vector(VL, f32);

    // One explicit-Euler Oregonator update. f v (u-q)/(u+q) = f v u/(u+q) - f v q/(u+q):
    // the first part is taken implicitly in u, which keeps the stiff refractory zone stable.
    inline fn cellV(uc: V, vc: V, lap: V, k: f32, kd: f32) [2]V {
        const q: V = @splat(Q);
        const kv: V = @splat(k);
        const fq: V = @splat(F);
        const one: V = @splat(1.0);
        const inv = one / (uc + q);
        const expl = uc + kv * (uc - uc * uc + fq * vc * q * inv) + @as(V, @splat(kd)) * lap;
        const un = @min(one, @max(@as(V, @splat(0.0)), expl / (one + kv * fq * vc * inv)));
        const vn = vc + @as(V, @splat(SDT)) * (uc - vc);
        return .{ un, vn };
    }

    fn substep(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const src = self.cur;
        const dst = 1 - src;
        const u = &self.u[src];
        const v = &self.v[src];
        const un = &self.u[dst];
        const vn = &self.v[dst];
        const k: f32 = SDT / EPS;
        const kd: f32 = SDT * DU / (H * H);

        for (0..gh) |j| {
            const jm = if (j == 0) gh - 1 else j - 1;
            const jp = if (j + 1 == gh) 0 else j + 1;
            const r = j * gw;
            const rm = jm * gw;
            const rp = jp * gw;
            // Interior cells, 8 at a time (no wrap needed).
            var i: usize = 1;
            while (i + VL < gw) : (i += VL) {
                const uc: V = u[r + i ..][0..VL].*;
                const vc: V = v[r + i ..][0..VL].*;
                const ul: V = u[r + i - 1 ..][0..VL].*;
                const ur: V = u[r + i + 1 ..][0..VL].*;
                const uu: V = u[rm + i ..][0..VL].*;
                const ud: V = u[rp + i ..][0..VL].*;
                const res = cellV(uc, vc, ul + ur + uu + ud - @as(V, @splat(4.0)) * uc, k, kd);
                un[r + i ..][0..VL].* = res[0];
                vn[r + i ..][0..VL].* = res[1];
            }
            // Remaining cells (wrap at the left and right edges).
            var ii: usize = 0;
            while (ii < gw) : (ii += 1) {
                if (ii >= 1 and ii < i) {
                    ii = i - 1;
                    continue;
                }
                const im = if (ii == 0) gw - 1 else ii - 1;
                const ip = if (ii + 1 == gw) 0 else ii + 1;
                const uc = u[r + ii];
                const vc = v[r + ii];
                const lap = u[r + im] + u[r + ip] + u[rm + ii] + u[rp + ii] - 4.0 * uc;
                const res = cellV(@splat(uc), @splat(vc), @splat(lap), k, kd);
                un[r + ii] = res[0][0];
                vn[r + ii] = res[1][0];
            }
        }
        self.cur = dst;
        self.sim_t += SDT;
    }

    fn pacemakers(self: *State) void {
        if (self.sim_t < self.pm_next) return;
        self.pm_next = self.sim_t + PM_PERIOD;
        const gw = self.gw;
        const gh = self.gh;
        const u = &self.u[self.cur];
        const v = &self.v[self.cur];
        for (0..N_PM) |p| {
            const px = self.pm_x[p];
            const py = self.pm_y[p];
            if (v[py * gw + px] > 0.04) continue; // still refractory: no firing
            var dy: isize = -2;
            while (dy <= 2) : (dy += 1) {
                var dx: isize = -2;
                while (dx <= 2) : (dx += 1) {
                    const yy: usize = @intCast(@mod(@as(isize, @intCast(py)) + dy, @as(isize, @intCast(gh))));
                    const xx: usize = @intCast(@mod(@as(isize, @intCast(px)) + dx, @as(isize, @intCast(gw))));
                    u[yy * gw + xx] = 0.9;
                }
            }
        }
    }

    fn colorize(self: *State) void {
        const n = self.gw * self.gh;
        const v = &self.v[self.cur];
        const u = &self.u[self.cur];
        for (0..n) |i| {
            const ox = math.clamp(@max(v[i], 0.25 * u[i]) / VMAX, 0.0, 1.0);
            const k: usize = @intFromFloat(ox * 255.0);
            const c = self.lut[k];
            const s: u64 = @intFromFloat(self.vig[i] * 256.0);
            self.col[i] = ((c * s) >> 8) & 0x0000_00FF_00FF_00FF;
        }
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.acc += @max(0.0, dt) * SIM_RATE;
        const sdt: f64 = SDT;
        var n: usize = 0;
        while (self.acc >= sdt and n < MAX_SUB) : (n += 1) {
            self.acc -= sdt;
            self.substep();
        }
        if (self.acc > sdt) self.acc = 0.0;
        self.pacemakers();
        self.colorize();
    }

    inline fn lerp64(a: u64, b: u64, t: u64) u64 {
        return ((a * (256 - t) + b * t) >> 8) & 0x0000_00FF_00FF_00FF;
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const gw = self.gw;
        var tmp: [MAX_GW]u64 = undefined;
        for (0..self.h) |y| {
            const j0: usize = self.yi[y];
            const ty: u64 = self.yt[y];
            const r0 = self.col[j0 * gw .. j0 * gw + gw];
            const r1 = self.col[(j0 + 1) * gw .. (j0 + 1) * gw + gw];
            for (tmp[0..gw], r0, r1) |*t, a, b| t.* = lerp64(a, b, ty);
            const dst = buf[y * stride .. y * stride + w];
            for (dst, self.xi[0..w], self.xt[0..w]) |*d, ix, tx| {
                const c = lerp64(tmp[ix], tmp[ix + 1], tx);
                d.* = @as(u32, @truncate((c & 0xFF) | ((c >> 8) & 0xFF00) | ((c >> 16) & 0xFF0000))) | 0xFF000000;
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        const u = &self.u[self.cur];
        const v = &self.v[self.cur];
        const n = self.gw * self.gh;
        var i: usize = 0;
        while (i < n) : (i += 97) {
            if (math.isNan(u[i]) or math.isNan(v[i]) or math.isInf(v[i])) return true;
        }
        return math.isNan(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}
