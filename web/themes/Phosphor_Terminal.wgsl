// PHOSPHOR TERMINAL // themes/Phosphor_Terminal.metal
// The WGSL translation of themes/Phosphor_Terminal.metal, one to one, for Argus's browser WebGPU runtime.
// Claude (Anthropic), 2026-10-19.
//
// What you see: this Mac's vital signs on a green-phosphor terminal that fills the screen behind a
// painted-steel bezel: a long-persistence (P39) monochrome tube of the IBM 5151 class, 400 scan lines,
// text on a fixed 128 x 40 character grid in the DEC VT320's dot font (one dot row per scan line), charts
// drawn in graphics as on a VT340-class graphics terminal; the title in double-width characters.
// The machine is drawn as a schematic of its chip (one block per core, efficiency and performance
// cores apart, the GPU, two memory packages), with the CPU load, the per-cluster averages and the GPU
// beside it; sweep charts of CPU (120 s, peak and average) and network (60 s), memory,
// the user's busiest processes, power, disk, thermal state, uptime and the local date and time. After
// each sample (about once a second) the screen repaints top to bottom; changed characters leave a dim
// P39 ghost; chart heads write the newest stretch brightest; a log line types itself at 300 baud.
// Nothing is bright while all is well: only abnormal states (memory pressure, thermal state, low
// battery) go to reverse video, and the serious ones blink.
//
// Readings (all from `@argus stats`, sampled by Argus ~1/s while this Space is on screen):
//   CPU LOAD / per-core blocks: cpu_total, cpu_core[] (busy fraction; efficiency cores numbered first,
//     split by cpu_e_cores / cpu_p_cores; "C1.." when the Mac doesn't say). GPU block: gpu_busy
//     (IOAccelerator Device Utilization). MEMORY: mem_used_gb (Activity Monitor's Memory Used) of
//     mem_total_gb; wired and compressed as reported, APP = used - wired - compressed; SWAP; PRESSURE =
//     mem_pressure (NORMAL / WARN / CRITICAL, Activity Monitor's green / yellow / red). NETWORK: net_rx_bps
//     / net_tx_bps of all active interfaces, full scale = the last minute's peak on a 1-2-5 ladder.
//     PROCESS: the user's own top processes by CPU; % CPU as Activity Monitor counts it (one core = 100,
//     = cpu x cpu_count x 100), MEM GB = their footprint; a full bar = a quarter of the machine. BATT:
//     charge, charging, minutes left / to full (CALCULATING while macOS estimates; AC POWER on desktops).
//     DISK: free GB of the startup volume (decimal, purgeable space excluded). THERMAL: thermalState.
//     UP: uptime_s. Date and time: ArgusFrame (local time zone, daylight saving included).
//
// Sources ([cited] page read, [snippet] search result only, [looked at] photo; notes in the session folder):
//   - IBM 5151 monochrome display: P39 phosphor, high persistence that smears on change [cited, Wikipedia
//     "IBM 5151"]; P39 = Zn2SiO4:Mn,As, the long-persistence willemite, ~150 ms to the 10 % point
//     [snippet, patent search result]; willemite emits at 525 nm [cited, Jankowiak phosphor table],
//     colour point x 0.21, y 0.71 [snippet, US4559469] -> the phosphor colour and the ghosting below.
//   - Halation: light reflected inside the faceplate relights the phosphor around bright strokes
//     [cited, US4310784] -> a soft glow around lit strokes (see CHOSEN for its size).
//   - Beam spot grows with beam current, so bright strokes fatten [snippet] -> spot width 0.24-0.44 pitch.
//   - Glass reflects ~4 % per surface; tinted faceplates pass 30-75 % [cited, US4996459 / US5760540]
//     -> a dark tinted face with a faint soft room reflection.
//   - MDA text attributes: normal, bright, reverse, blink, underline [cited, Wikipedia "IBM Monochrome
//     Display Adapter"] -> the only emphasis used: bright, reverse video (whole character cells), blink.
//   - VT323 (Peter Hull, SIL OFL 1.1, google/fonts): the DEC VT320's glyphs on their dot grid, caps 7 dot
//     rows, descenders 2 [looked at the outlines: 80 units a row, 0.4 em advance] -> one dot row per scan
//     line, a 15 x 30 px cell (10 lines); rendered into Phosphor_Terminal.bin (licence:
//     Phosphor_Terminal_OFL.txt). The VT100 drew a 7 x 9 dot glyph in a 10 x 10 cell [cited, vt100.net
//     technical manual] -> the 10-line cell; DEC's double-width lines (DECDWL) [from memory, not re-read]
//     -> the title.
//   - The Fallout games' terminals and wrist computer [cited, fallout.wiki]: tabbed header line, segmented
//     bars, uppercase labels, text typed out -> the look; their names, logos and fonts are not used.
//   - Dark cockpit: a healthy cockpit shows no lights [cited, Flightglobal on Airbus] -> warnings only.
// COMPUTED (from the data or the model, not tuned by eye):
//   - every number and bar above, from the live sample; dates from ArgusFrame (civil calendar from JDN);
//   - phosphor colour: x 0.21, y 0.71 is outside sRGB; clipped per channel it is pure green (0, 1, 0);
//   - persistence: emission after the beam leaves = 0.992 exp(-t / 65 ms) + 0.008 exp(-t / 0.8 s): the
//     fast part puts the 10 % point near 150 ms;
//   - typing speed: 300 baud with 10 bits per character = 30 characters a second.
// CHOSEN (taste or calibration, not measured):
//   - 400 scan lines (the 5151 shows 350) for 40 text rows; a DEC font on an IBM-class tube; the big
//     readout is the same glyphs scaled 5x (a software big font); the slow tail (0.8 %, 0.8 s) is a guess
//     for "fades over seconds"; a 4 % red and
//     7 % blue floor on the phosphor green so faint strokes don't go neon;
//   - the chip: a schematic, not to scale: package with a pin-1 mark, the die, the memory as two
//     packages beside it (how many packages a Mac has is not modelled); a full process bar = a quarter
//     of the machine;
//   - glow (halation and bloom) as a 6 px soft halo, not the patent's disc 3.5x the glass thickness;
//   - repaint top to bottom over 4 ticks (0.13 s) after each sample, cut at gaps in the layout; chart
//     heads one sample behind the newest so traces are written continuously (1 s display latency);
//     a monotone cubic between samples (no overshoot); where samples are missing (this Space was
//     hidden) the trace breaks;
//   - block levels damped critically, 99 % in ~0.66 s (omega 10/s, from the VU-meter family of ballistics,
//     slowed); blink 1 Hz; an underline cursor blinking at 1 Hz; log messages every 10 s;
//   - the faint rolling band (5 %, 40 s) is a camera artefact on real CRTs, kept for the look;
//   - the room reflection, bezel paint and chamfer, curvature (2.5 %); the face fits any screen shape.
// NOT MODELLED: interlace and refresh flicker (P39 hides 50 Hz flicker), burn-in, dot structure of a
//   ROM character generator, geometric distortion beyond the barrel curve, the 5151's etched anti-glare.
// CHECKED: harness PASS at 30 and 120 FPS; contact sheet (moments 0.1 s - 110 s, warning states, a forced
//   24P+8E layout); two independent reviews (look; motion and robustness), their findings fixed. Not checked
//   against a running 5151. Live stats of this Mac (`--stats live`) rendered and looked at.
// How it works: argus_step (30 Hz) paints what the beam writes into a 1920 x 400 scan-line buffer in the
//   state (texel: written, glow, fast ghost, slow tail), keeps history rings (256 samples) and damped block
//   levels; argus_draw samples two scan lines per pixel as Gaussian beams, adds the live block fills,
//   the glass and the bezel. State 1920 x 784 RGBA16F (12 MB, 24 MB with the ping-pong pair).
// Cost (busy shared machine, load ~3.4, alternated with Night Tide x3, 2026-10-19): 0.94 ms back-to-back
//   (0.42 step + 0.51 draw) vs Night Tide 2.61-2.76 ms (0.35x); paced 30 FPS 1.5-2.4 ms median, 60-84 ms of
//   GPU per second including the once-a-second repaint, vs Night Tide 172-188 ms (0.4x). 120 FPS: PASS.
//   After the VT323 grid change (load 6.4): 0.94 ms vs Night Tide 4.2 ms; 51-54 vs 124-140 ms GPU/s (0.4x).
//
// @argus state 1920x784
// @argus data Phosphor_Terminal.bin 1024x384 rgba8
// @argus stats

// ---------------------------------------------------------------------------------- layout
const VW: f32 = 1920.0;           // virtual canvas: 1920 x 1200, scaled to the screen height
const VH: f32 = 1200.0;
const LINES: i32 = 400;           // scan lines on the face
const PITCH: f32 = 3.0;           // virtual px per scan line
const ATLAS_Y: u32 = 400u;        // glyph atlas rows in the state
const HIST_X: u32 = 1024u; const HIST_Y: u32 = 400u;   // history rings: 256 samples per series, one row each
const META_X: u32 = 1024u; const META_Y: u32 = 420u;   // bookkeeping texels
const MSG_Y: u32 = 421u;                               // the log message, one character per texel
const CELL: f32 = 64.0; const SPREAD: f32 = 8.0; const EMPX: f32 = 50.0; const FBASE: f32 = 0.75;   // atlas: 50 px per em, baseline at 48
const ADV: f32 = 0.4;             // VT323 advance, em: a 15 x 30 px cell at 37.5 px per em
const FACE_C = vec2f(960.0, 600.0); const FACE_H = vec2f(905.0, 565.0);
const FACE_R: f32 = 80.0; const FACE_K: f32 = 0.025;
// text sizes (em, virtual px): cap height = 0.698 em lands on whole scan lines
// VT323 draws on a dot grid: 80 font units a dot row, caps 7 rows. At 37.5 px per em one dot row is one scan
// line (3 px), so the character cell is 15 x 30 px (10 lines): 128 columns x 40 rows. Text sits on that grid
// (baseline of row r at y = 30 r + 24); the big readout is the same glyphs at 5x.
const EM_N: f32 = 37.5; const EM_B: f32 = 187.5;
// Metal's round(): halfway cases away from zero (WGSL's round() rounds them to even).
fn mround(x: f32) -> f32 { let t = trunc(x); return select(t, t + sign(x), abs(x - t) >= 0.5); }
fn gx(x: f32) -> f32 { return 15.0 * mround(x / 15.0); }
fn gbase_at_or_below(ytop: f32) -> f32 { return 30.0 * ceil((ytop - 3.0) / 30.0) + 24.0; }
// phosphor: P39 (Zn2SiO4:Mn,As) falls to ~10 % in ~150 ms; a small slow tail
const TAU_FAST: f32 = 0.065; const TAU_TAIL: f32 = 0.8; const TAIL: f32 = 0.008;
const OMEGA: f32 = 10.0;          // block levels: critically damped, 99 % in ~0.66 s
// series in the history rings
const SER_CPU: u32 = 0u; const SER_GPU: u32 = 1u; const SER_RX: u32 = 2u; const SER_TX: u32 = 3u;
const CPU_N: f32 = 120.0; const NET_N: f32 = 60.0;   // samples across each chart

fn sq(x: f32) -> f32 { return x * x; }
fn sd_box(p: vec2f, c: vec2f, hw: vec2f, r: f32) -> f32 {
    let q = abs(p - c) - hw + r;
    return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
fn over(c: vec3f, x: vec3f, a: f32) -> vec3f { return mix(c, x, saturate(a)); }
fn wrap_dt(d: f32) -> f32 { return select(max(d, 0.0), d + ARGUS_TIME_PERIOD, d < -1.0); }
fn split_time(t: f32) -> vec4f { let a = floor(t / 1024.0); let b = floor(t - a * 1024.0); return vec4f(a, b, t - a * 1024.0 - b, 0.0); }
fn join_time(v: vec4f) -> f32 { return v.x * 1024.0 + v.y + v.z; }

// ---------------------------------------------------------------------------------- text
// (Metal's RTex pv, the state read in argus_step, is the prelude's argus_state here.)
// Strings: WGSL has no char arrays, so every constant string is a (start, length) pair into the table STR
// below, and a thread char buffer is a Buf of character codes passed by pointer (b + n in Metal is (b, n)).
alias Buf = array<u32, 64>;
fn str_char(s: vec2u, i: i32) -> u32 { return STR[s.x + u32(i)]; }
// signed distance (atlas px, + inside) of glyph c at q (atlas px in its cell, y down); manual bilinear
fn glyph_sd(c: i32, font: i32, q_in: vec2f) -> f32 {
    let g = clamp(c - 32, 0, 95);
    let q = clamp(q_in, vec2f(0.5), vec2f(CELL - 0.5)) - 0.5;
    let o = vec2f(f32(g & 15), f32(g >> 4u)) * CELL + vec2f(0.0, f32(ATLAS_Y));
    let i = floor(q); let w = q - i;
    let p = vec2u(o + i);
    let p1 = min(p + 1u, textureDimensions(argus_state) - 1u); // the (0-weight) far taps stay inside
    let a = textureLoad(argus_state, p, 0); let b = textureLoad(argus_state, vec2u(p1.x, p.y), 0);
    let c2 = textureLoad(argus_state, vec2u(p.x, p1.y), 0); let d = textureLoad(argus_state, p1, 0);
    let v = mix(mix(a, b, w.x), mix(c2, d, w.x), w.y);
    return (select(v.y, v.x, font == 0) - 0.5) * 2.0 * SPREAD;
}
// monospace string, baseline-left at org, em size em: signed distance in virtual px (+ inside)
// (Metal: one template over the string's type. WGSL has no templates, so three copies that differ only in
// where character i comes from: text_sd a thread buffer, text_sd_c a constant string, text_sd_p a process name.)
fn text_sd(p: vec2f, org: vec2f, em: f32, s: ptr<function, Buf>, n: i32, font: i32, xs: f32) -> f32 {
    let adv = ADV * em * xs; let sc = em / EMPX;
    let q = p - org;
    if (q.y < -0.9 * em || q.y > 0.35 * em || q.x < -0.5 * adv || q.x > (f32(n) + 0.5) * adv) { return -1e3; }
    let i0 = i32(floor(q.x / adv));
    var best = -1e3;
    for (var j = -1; j <= 1; j++) {
        let i = i0 + j;
        if (i < 0 || i >= n) { continue; }
        let c = i32((*s)[i]);
        if (c <= 32) { continue; }
        best = max(best, glyph_sd(c, font, vec2f((q.x - f32(i) * adv) / (sc * xs) + SPREAD, q.y / sc + FBASE * CELL)));
    }
    return best * sc;
}
fn text_sd_c(p: vec2f, org: vec2f, em: f32, s: vec2u, n: i32, font: i32, xs: f32) -> f32 {
    let adv = ADV * em * xs; let sc = em / EMPX;
    let q = p - org;
    if (q.y < -0.9 * em || q.y > 0.35 * em || q.x < -0.5 * adv || q.x > (f32(n) + 0.5) * adv) { return -1e3; }
    let i0 = i32(floor(q.x / adv));
    var best = -1e3;
    for (var j = -1; j <= 1; j++) {
        let i = i0 + j;
        if (i < 0 || i >= n) { continue; }
        let c = i32(str_char(s, i));
        if (c <= 32) { continue; }
        best = max(best, glyph_sd(c, font, vec2f((q.x - f32(i) * adv) / (sc * xs) + SPREAD, q.y / sc + FBASE * CELL)));
    }
    return best * sc;
}
fn text_sd_p(p: vec2f, org: vec2f, em: f32, s: u32, n: i32, font: i32, xs: f32) -> f32 {
    let adv = ADV * em * xs; let sc = em / EMPX;
    let q = p - org;
    if (q.y < -0.9 * em || q.y > 0.35 * em || q.x < -0.5 * adv || q.x > (f32(n) + 0.5) * adv) { return -1e3; }
    let i0 = i32(floor(q.x / adv));
    var best = -1e3;
    for (var j = -1; j <= 1; j++) {
        let i = i0 + j;
        if (i < 0 || i >= n) { continue; }
        let c = i32(argus_proc_char(s, u32(i)));
        if (c <= 32) { continue; }
        best = max(best, glyph_sd(c, font, vec2f((q.x - f32(i) * adv) / (sc * xs) + SPREAD, q.y / sc + FBASE * CELL)));
    }
    return best * sc;
}
fn tw(n: i32, em: f32) -> f32 { return f32(n) * ADV * em; }
fn slen(s: vec2u) -> i32 { return min(i32(s.y), 63); }
fn pname_len(pi: u32) -> i32 { var n = 0; while (n < 31 && argus_proc_char(pi, u32(n)) != 0u) { n++; } return n; }
fn fmt(b: ptr<function, Buf>, bo: i32, v: f32, dec: i32, minint: i32) -> i32 {
    var m = 1.0; for (var i = 0; i < dec; i++) { m *= 10.0; }
    let x = i32(floor(max(v, 0.0) * m + 0.5));
    var t: array<u32, 14>; var nd = 0;
    var ip = x; for (var i = 0; i < dec; i++) { ip /= 10; }
    var fp = x - ip * i32(m);
    for (var i = 0; i < dec; i++) { t[nd] = u32(48 + fp % 10); nd++; fp /= 10; }   // '0' + digit
    if (dec > 0) { t[nd] = 46u; nd++; }                                             // '.'
    var k = 0; loop { t[nd] = u32(48 + ip % 10); nd++; ip /= 10; k++; if (!((ip > 0 || k < minint) && nd < 13)) { break; } }
    for (var i = 0; i < nd; i++) { (*b)[bo + i] = t[nd - 1 - i]; }
    return nd;
}
fn cat(b: ptr<function, Buf>, n_in: i32, s: vec2u) -> i32 { var n = n_in; var i = 0; while (i < i32(s.y) && n < 63) { (*b)[n] = str_char(s, i); n++; i++; } return n; }
fn catb(b: ptr<function, Buf>, n_in: i32, s: ptr<function, Buf>, m: i32) -> i32 { var n = n_in; for (var i = 0; i < m && n < 63; i++) { (*b)[n] = (*s)[i]; n++; } return n; }
fn cat2(b: ptr<function, Buf>, n_in: i32, v: i32) -> i32 { var n = n_in; (*b)[n] = u32(48 + (v / 10) % 10); n++; (*b)[n] = u32(48 + v % 10); n++; return n; }
// a rate in bytes/s as "840 KB/S" or "2.4 MB/S"
const U_KBS = vec2u(0u, 5u);   // " KB/S"
const U_MBS = vec2u(5u, 5u);   // " MB/S"
fn fmt_rate(b: ptr<function, Buf>, n_in: i32, bps: f32) -> i32 {
    var n = n_in;
    if (bps < 1e6) { n += fmt(b, n, bps / 1e3, select(0, 1, bps < 1e4), 1); return cat(b, n, U_KBS); }
    n += fmt(b, n, bps / 1e6, select(0, 1, bps < 1e7), 1); return cat(b, n, U_MBS);
}

// ---------------------------------------------------------------------------------- the machine's blocks
struct Blk { c: vec2f, h: vec2f, }
fn grid_block(i: i32, n: i32, lo: vec2f, hi: vec2f) -> Blk {
    let sz = hi - lo;
    let cols = clamp(i32(mround(sqrt(f32(n) * sz.x / sz.y))), 1, max(n, 1));
    let rows = (n + cols - 1) / cols;
    let cell = sz / vec2f(f32(cols), f32(rows));
    var b: Blk; b.c = lo + (vec2f(f32(i % cols), f32(i / cols)) + 0.5) * cell; b.h = 0.5 * cell - 7.0;
    return b;
}
fn typed_cores() -> bool { return s.cpu_p_cores + s.cpu_e_cores == s.cpu_count && s.cpu_p_cores > 0u; }
// block i: 0..count-1 the cores in the kernel's order (efficiency first), count = the GPU
fn block(i: i32) -> Blk {
    let n = i32(min(s.cpu_count, 32u));
    if (i >= n) { var g: Blk; g.c = vec2f(590.0, 356.0); g.h = vec2f(120.0, 106.0); return g; }
    if (!typed_cores()) { return grid_block(i, n, vec2f(185, 245), vec2f(450, 560)); }
    let e = i32(s.cpu_e_cores);
    let eh = select(110.0, 75.0, e <= 4);
    if (i < e) { return grid_block(i, e, vec2f(185.0, 560.0 - eh), vec2f(450, 560)); }
    return grid_block(i - e, n - e, vec2f(185, 245), vec2f(450.0, 545.0 - eh));
}
fn block_label(b: ptr<function, Buf>, i_in: i32) -> i32 {
    var i = i_in;
    let n = i32(min(s.cpu_count, 32u)); var k = 0;
    if (i >= n) { (*b)[0] = 71u; (*b)[1] = 80u; (*b)[2] = 85u; return 3; }   // "GPU"
    if (!typed_cores()) { (*b)[k] = 67u; k++; }                                // 'C'
    else if (i < i32(s.cpu_e_cores)) { (*b)[k] = 69u; k++; }                    // 'E'
    else { (*b)[k] = 80u; k++; i -= i32(s.cpu_e_cores); }                       // 'P'
    return k + fmt(b, k, f32(i + 1), 0, 1);
}

// ---------------------------------------------------------------------------------- content: what the beam writes
struct Meta {
    t_arr: f32,      // f.time when the newest sample arrived
    scale_net: f32,  // network chart full scale, MB/s
    hv: i32,         // newest sample already in the history rings (the newest one lands a tick later)
}
fn histv(ser: u32, g: i32) -> vec2f { return textureLoad(argus_state, vec2u(HIST_X + u32(g & 255), HIST_Y + ser), 0).xy; }
fn hist(ser: u32, g: i32) -> f32 { return histv(ser, g).x; }
fn hok(g: i32, lo: i32, hi: i32) -> bool { return g >= lo && g <= hi && histv(SER_CPU, g).y > 0.5; }
// monotone cubic (Fritsch-Butland) through the samples around global sample coordinate g (clamped to [lo, hi])
fn hist_at(ser: u32, g: f32, lo: i32, hi: i32) -> f32 {
    let gf = floor(g); let t = g - gf; let i = i32(gf);
    let p1 = hist(ser, clamp(i, lo, hi));
    let p2 = select(p1, hist(ser, i + 1), hok(i + 1, lo, hi));
    let p0 = select(p1, hist(ser, i - 1), hok(i - 1, lo, hi));
    let p3 = select(p2, hist(ser, i + 2), hok(i + 2, lo, hi));
    let d0 = p1 - p0; let d1 = p2 - p1; let d2 = p3 - p2;
    let m1 = select(0.0, 2.0 * d0 * d1 / (d0 + d1), d0 * d1 > 0.0);
    let m2 = select(0.0, 2.0 * d1 * d2 / (d1 + d2), d1 * d2 > 0.0);
    let t2 = t * t; let t3 = t2 * t;
    return (2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2;
}
fn seg_d(p: vec2f, a: vec2f, b: vec2f) -> f32 {
    let pa = p - a; let ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6)));
}
// distance from S to the trace of series ser drawn over a chart (x0..x1, y0..y1), sample coordinate g at S.x,
// N samples across, value / div mapped to the height; a 7-point polyline around the column
fn trace_d(ser: u32, S: vec2f, g: f32, N: f32, x0: f32, x1: f32, y0: f32, y1: f32, div: f32, lo: i32, hi: i32) -> f32 {
    let gpx = N / (x1 - x0);   // samples per px
    var d = 1e3; var prev = vec2f(0.0); var okp = false;
    for (var k = -3; k <= 3; k++) {
        let dx = f32(k) * 2.0;
        let gk = clamp(g + dx * gpx, f32(lo), f32(hi));
        let gi = i32(floor(gk));
        let ok = hok(gi, lo, hi) && (gk == f32(gi) || hok(gi + 1, lo, hi));
        let pk = vec2f(S.x + dx, y1 - (y1 - y0) * saturate(hist_at(ser, gk, lo, hi) / div));
        if (k > -3 && ok && okp) { d = min(d, seg_d(S, prev, pk)); }
        prev = pk; okp = ok;
    }
    return d;
}
// distance to the write head's spot (the newest point of the trace), so the trace ends in a round glow
fn head_d(ser: u32, S: vec2f, h: f32, N: f32, x0: f32, x1: f32, y0: f32, y1: f32, div: f32, lo: i32, hi: i32) -> f32 {
    let xh = x0 + (x1 - x0) * fract(h / N);
    let yh = y1 - (y1 - y0) * saturate(hist_at(ser, clamp(h, f32(lo), f32(hi)), lo, hi) / div);
    return length(S - vec2f(xh, yh));
}
fn put_text(a: ptr<function, vec2f>, sd: f32, em: f32, b: f32) {
    (*a).x = max((*a).x, b * saturate(sd + 0.5));
    let sp = SPREAD * em / EMPX;
    (*a).y = max((*a).y, b * select(1.0, 0.55, em < 25.0) * exp(min(sd, 0.0) / 5.0) * saturate((sd + 0.85 * sp) / (0.25 * sp)));
}
fn put_rev(a: ptr<function, vec2f>, sd: f32, S: vec2f, org: vec2f, n: i32, em: f32, b: f32) {
    // reverse video: a lit cell box with the glyph cut out of it
    let box = sd_box(S, org + vec2f(0.5 * tw(n, em), -9.0), vec2f(0.5 * tw(n, em), 15.0), 0.0);   // the cells
    let v = b * saturate(0.5 - box) * (1.0 - saturate(sd + 0.5));
    (*a).x = max((*a).x, v); (*a).y = max((*a).y, b * saturate(0.5 - box) * 0.6);
}
fn put_line(a: ptr<function, vec2f>, d: f32, w: f32, b: f32) {
    (*a).x = max((*a).x, b * saturate(w + 0.5 - d));
    (*a).y = max((*a).y, b * exp(-max(d - w, 0.0) / 4.5));
}
fn put_fill(a: ptr<function, vec2f>, sd: f32, b: f32) {
    (*a).x = max((*a).x, b * saturate(0.5 - sd));
    (*a).y = max((*a).y, b * exp(-max(sd, 0.0) / 6.0));
}
fn seg_bar(a: ptr<function, vec2f>, S: vec2f, x0: f32, y0: f32, cells: i32, cw: f32, h: f32, v: f32, b: f32) {
    if (S.y < y0 - h || S.y > y0 || S.x < x0 || S.x > x0 + f32(cells) * cw) { return; }
    let cx = (S.x - x0) / cw; let ci = i32(cx); let fx = cx - f32(ci);
    if (fx > 0.14 && fx < 0.86) {
        if (f32(ci) + 0.5 < v * f32(cells)) { put_fill(a, -1.0, b); }
        else { put_line(a, min(min(fx - 0.14, 0.86 - fx) * cw, min(S.y - (y0 - h), y0 - S.y)), 0.7, b * 0.30); }
    }
}
// (Metal's TX / TXR / TB / TBR macros, as functions: `a` and `S` are passed explicitly. TBC is TB for a
// constant string, TBP for a process name: the template instantiations Metal's macros reached.)
fn TX(a: ptr<function, vec2f>, S: vec2f, str: vec2u, x: f32, y: f32, em: f32, b: f32) { put_text(a, text_sd_c(S, vec2f(x, y), em, str, slen(str), 0, 1.0), em, b); }
fn TXR(a: ptr<function, vec2f>, S: vec2f, str: vec2u, x: f32, y: f32, em: f32, b: f32) { let n = slen(str); put_text(a, text_sd_c(S, vec2f(x - tw(n, em), y), em, str, n, 0, 1.0), em, b); }
fn TB(a: ptr<function, vec2f>, S: vec2f, buf: ptr<function, Buf>, n: i32, x: f32, y: f32, em: f32, b: f32) { put_text(a, text_sd(S, vec2f(x, y), em, buf, n, 0, 1.0), em, b); }
fn TBR(a: ptr<function, vec2f>, S: vec2f, buf: ptr<function, Buf>, n: i32, x: f32, y: f32, em: f32, b: f32) { put_text(a, text_sd(S, vec2f(x - tw(n, em), y), em, buf, n, 0, 1.0), em, b); }
fn TBC(a: ptr<function, vec2f>, S: vec2f, str: vec2u, n: i32, x: f32, y: f32, em: f32, b: f32) { put_text(a, text_sd_c(S, vec2f(x, y), em, str, n, 0, 1.0), em, b); }
fn TBP(a: ptr<function, vec2f>, S: vec2f, pi: u32, n: i32, x: f32, y: f32, em: f32, b: f32) { put_text(a, text_sd_p(S, vec2f(x, y), em, pi, n, 0, 1.0), em, b); }


const H_TITLE = vec2u(10u, 20u);   // "ARGUS SYSTEM MONITOR"
const H_SOC = vec2u(30u, 3u);   // "SOC"
const H_WAIT = vec2u(33u, 18u);   // "AWAITING TELEMETRY"
const T_GPU = vec2u(51u, 3u);   // "GPU"
const T_UM = vec2u(54u, 14u);   // "UNIFIED MEMORY"
const T_GB = vec2u(68u, 3u);   // " GB"
const T_CPU = vec2u(71u, 8u);   // "CPU LOAD"
const T_CPUC = vec2u(79u, 10u);   // "CPU  120 S"
const T_PEAK = vec2u(89u, 5u);   // "PEAK "
const T_AVG = vec2u(94u, 6u);   // "  AVG "
const T_FS100 = vec2u(100u, 15u);   // "FULL SCALE 100%"
const T_PCL = vec2u(115u, 9u);   // "P CLUSTER"
const T_ECL = vec2u(124u, 9u);   // "E CLUSTER"
const T_LPDDR = vec2u(133u, 5u);   // "LPDDR"
const T_NET = vec2u(138u, 13u);   // "NETWORK  60 S"
const T_RX = vec2u(151u, 3u);   // "RX "
const T_TX = vec2u(154u, 6u);   // "   TX "
const T_FS = vec2u(160u, 11u);   // "FULL SCALE "
const T_MEM = vec2u(171u, 6u);   // "MEMORY"
const T_OF = vec2u(177u, 3u);   // " / "
const T_PR = vec2u(180u, 9u);   // "PRESSURE "
const T_PRS0 = vec2u(189u, 6u);   // "NORMAL"
const T_PRS1 = vec2u(195u, 4u);   // "WARN"
const T_PRS2 = vec2u(199u, 8u);   // "CRITICAL"
const T_LW = vec2u(207u, 5u);   // "WIRED"
const T_LA = vec2u(212u, 3u);   // "APP"
const T_LC = vec2u(215u, 10u);   // "COMPRESSED"
const T_LF = vec2u(225u, 4u);   // "FREE"
const T_SWAP = vec2u(229u, 5u);   // "SWAP "
const T_PROC = vec2u(234u, 7u);   // "PROCESS"
const T_PCPU = vec2u(241u, 5u);   // "% CPU"
const T_PMEM = vec2u(246u, 6u);   // "MEM GB"
const T_PCT = vec2u(252u, 1u);   // "%"
const T_BATT = vec2u(253u, 5u);   // "BATT "
const T_AC = vec2u(258u, 8u);   // "AC POWER"
const T_CHG = vec2u(266u, 9u);   // " CHARGING"
const T_LEFT = vec2u(275u, 5u);   // " LEFT"
const T_CALC = vec2u(280u, 12u);   // " CALCULATING"
const T_TOFULL = vec2u(292u, 8u);   // " TO FULL"
const T_DISK = vec2u(300u, 5u);   // "DISK "
const T_FREE = vec2u(305u, 8u);   // " GB FREE"
const T_TH = vec2u(313u, 8u);   // "THERMAL "
const T_TH0 = vec2u(321u, 7u);   // "NOMINAL"
const T_TH1 = vec2u(328u, 4u);   // "FAIR"
const T_TH2 = vec2u(332u, 7u);   // "SERIOUS"
const T_TH3 = vec2u(339u, 8u);   // "CRITICAL"
const T_UP = vec2u(347u, 3u);   // "UP "
const T_D = vec2u(350u, 2u);   // "D "
const DAYS = vec2u(352u, 21u);   // "SUNMONTUEWEDTHUFRISAT"
fn press_word(p: u32) -> vec2u { return select(select(T_PRS2, T_PRS1, p == 1u), T_PRS0, p == 0u); }
fn therm_word(t: u32) -> vec2u { return select(select(select(T_TH3, T_TH2, t == 2u), T_TH1, t == 1u), T_TH0, t == 0u); }

// local civil date and time from the ArgusFrame clock
fn fmt_datetime(b: ptr<function, Buf>) -> i32 {
    let loc = argus_utc_seconds(f) + f32(f.utc_offset_s);
    let dshift = i32(floor(loc / 86400.0));
    let sec = loc - f32(dshift) * 86400.0;
    // days_j2000 counts from noon; day_frac >= 0.5 means past midnight UTC of the next civil day
    let jdn = 2451545 + f.days_j2000 + select(0, 1, f.day_frac >= 0.5) + dshift;
    var l = jdn + 68569; let nn = 4 * l / 146097; l = l - (146097 * nn + 3) / 4;
    let ii = 4000 * (l + 1) / 1461001; l = l - 1461 * ii / 4 + 31;
    let jj = 80 * l / 2447; let day = l - 2447 * jj / 80; l = jj / 11;
    let mon = jj + 2 - 12 * l; let yr = 100 * (nn - 49) + ii + l;
    let wd = (jdn + 1) % 7;
    var n = 0;
    for (var i = 0; i < 3; i++) { (*b)[n] = str_char(DAYS, wd * 3 + i); n++; }
    (*b)[n] = 32u; n++; n += fmt(b, n, f32(yr), 0, 4); (*b)[n] = 45u; n++; n = cat2(b, n, mon); (*b)[n] = 45u; n++; n = cat2(b, n, day);   // ' ', '-'
    (*b)[n] = 32u; n++; (*b)[n] = 32u; n++;
    let si = i32(sec);
    n = cat2(b, n, si / 3600); (*b)[n] = 58u; n++; n = cat2(b, n, (si / 60) % 60); (*b)[n] = 58u; n++; n = cat2(b, n, si % 60);   // ':'
    return n;
}

// chart geometry
const CX0: f32 = 855.0; const CX1: f32 = 1785.0;
const CPU_Y0: f32 = 186.0; const CPU_Y1: f32 = 426.0; const NET_Y0: f32 = 486.0; const NET_Y1: f32 = 636.0;
// where the write head is, in samples: one sample behind the newest, advancing continuously
fn head_g(t_arr: f32) -> f32 {
    let ph = saturate(wrap_dt(f.time - t_arr) / max(s.sample_dt, 0.25));
    return f32(s.seq) - 1.0 + ph;
}
// age (samples behind the head) of the column at u in a chart of N samples
fn col_age(u: f32, h: f32, N: f32) -> f32 { return (h - u * N + 4.0 * N) % N; }

fn content(m: Meta, S: vec2f) -> vec2f {
    var a = vec2f(0.0);
    let B = 1.0; let M = 0.42; let Dm = 0.24;
    let live = s.seq > 0u;
    let blink = select(0.0, 1.0, fract(f.time) < 0.6);   // attribute blink, ~1 Hz (CHOSEN)
    // ---- header: the line steps up around the title, like a tab
    put_text(&a, text_sd_c(S, vec2f(150, 114), EM_N, H_TITLE, slen(H_TITLE), 0, 2.0), EM_N, B);   // double width
    if (S.y > 80 && S.y < 120 && S.x > 1100) { var b: Buf; let n = fmt_datetime(&b); TBR(&a, S, &b, n, 1785, 114, EM_N, M); }
    if (S.x > 120 && S.x < 1800 && S.y > 70 && S.y < 140) {
        let gx0 = 138.0; let gx1 = 162.0 + 2.0 * tw(20, EM_N);
        if (S.x < gx0 || S.x > gx1) { put_line(&a, abs(S.y - 130.5), 1.0, M); } else { put_line(&a, abs(S.y - 76.5), 1.0, M * 0.8); }
        put_line(&a, length(vec2f(min(abs(S.x - gx0), abs(S.x - gx1)), max(abs(S.y - 103.5) - 27.0, 0.0))), 1.0, M * 0.8);
    }
    // ---- the machine as a schematic: package, pins, one block per core, the GPU, unified memory
    if (S.x < 800 && S.y > 150 && S.y < 800) {
        // package (a pin-1 mark in its corner), the die inside it, two memory packages beside the die
        let co = sd_box(S, vec2f(445, 475), vec2f(300, 290), 14.0);
        put_line(&a, abs(co), 1.2, M);
        if (co < -3.0 && (S.x - 145.0) + (S.y - 185.0) < 34.0) { put_fill(&a, -1.0, Dm); }
        put_line(&a, abs(sd_box(S, vec2f(447, 400), vec2f(275, 172), 6.0)), 0.8, Dm);
        {   // "SOC  6P+4E  16 GB"
            var b: Buf; var n = cat(&b, 0, H_SOC); b[n] = 32u; n++; b[n] = 32u; n++;
            if (typed_cores()) { n += fmt(&b, n, f32(s.cpu_p_cores), 0, 1); b[n] = 80u; n++; b[n] = 43u; n++; n += fmt(&b, n, f32(s.cpu_e_cores), 0, 1); b[n] = 69u; n++; }   // 'P' '+' 'E'
            else { n += fmt(&b, n, f32(s.cpu_count), 0, 1); b[n] = 67u; n++; }   // 'C'
            b[n] = 32u; n++; b[n] = 32u; n++; n += fmt(&b, n, s.mem_total_gb, 0, 1); n = cat(&b, n, T_GB);
            if (live) { TB(&a, S, &b, n, 150, 174, EM_N, Dm); }
        }
        let nb = i32(min(s.cpu_count, 32u)) + 1;
        for (var i = 0; i < nb; i++) {
            let k = block(i);
            if (abs(S.x - k.c.x) > k.h.x + 10.0 || abs(S.y - k.c.y) > k.h.y + 30.0) { continue; }
            put_line(&a, abs(sd_box(S, k.c, k.h, 3.0)), 1.0, M);
            var b: Buf; let n = block_label(&b, i);
            let lby = gbase_at_or_below(k.c.y - k.h.y + 21.0);   // the first grid row inside the block
            if (lby > k.c.y + k.h.y - 2.0) { continue; }
            if (k.h.x >= 40.0) {
                TB(&a, S, &b, n, 15.0 * ceil((k.c.x - k.h.x + 5.0) / 15.0), lby, EM_N, B);
                var p: Buf; var v = s.gpu_busy; if (i < nb - 1) { v = s.cpu_core[i]; }
                var np = fmt(&p, 0, v * 100.0, 0, 1); np = cat(&p, np, T_PCT);
                if (live) { TBR(&a, S, &p, np, 15.0 * floor((k.c.x + k.h.x - 4.0) / 15.0), lby, EM_N, M); }
            } else if (k.h.x >= 0.5 * tw(n, EM_N) + 2.0) { TB(&a, S, &b, n, gx(k.c.x - 0.5 * tw(n, EM_N)), lby, EM_N, M); }
        }
        // unified memory in two packages: wired | app | compressed fill from the left, free left open
        if (S.y > 595.0 && S.y < 750.0) {
            let tot = max(s.mem_total_gb, 1.0);
            let app = max(s.mem_used_gb - s.mem_wired_gb - s.mem_compressed_gb, 0.0);
            for (var pk = 0; pk < 2; pk++) {
                let mc = vec2f(select(587.0, 307.0, pk == 0), 672.0); let mh = vec2f(130.0, 64.0);
                let md = sd_box(S, mc, mh, 3.0);
                if (md > 8.0) { continue; }
                put_line(&a, abs(md), 1.0, M);
                let u = (f32(pk) + (S.x - (mc.x - mh.x)) / (2.0 * mh.x)) * 0.5 * tot;
                if (live && md < -4.0 && S.y > mc.y - 6.0) {
                    if (u < s.mem_wired_gb) { put_fill(&a, -1.0, 0.75); }
                    else if (u < s.mem_wired_gb + app) { put_fill(&a, -1.0, 0.45); }
                    else if (u < s.mem_used_gb) { if (floor(S.y / PITCH) % 2.0 < 1.0) { put_fill(&a, -1.0, 0.45); } }
                }
                var b: Buf; var n = cat(&b, 0, T_LPDDR); b[n] = 32u; n++; b[n] = 32u; n++; n += fmt(&b, n, 0.5 * s.mem_total_gb, 0, 1); n = cat(&b, n, T_GB);
                TB(&a, S, &b, n, 15.0 * ceil((mc.x - mh.x + 6.0) / 15.0), 654.0, EM_N, M);
                let ng = clamp(i32(0.5 * tot), 1, 96);
                let gx = (S.x - (mc.x - mh.x)) / (2.0 * mh.x) * f32(ng);
                if (ng <= 32 && abs(S.y - (mc.y + 30.0)) < 30.0) { put_line(&a, abs(gx - mround(gx)) * 2.0 * mh.x / f32(ng), 0.6, Dm * step(0.5, gx) * step(gx, f32(ng) - 0.5)); }
            }
        }
    }
    // ---- big CPU readout
    if (S.x < 840 && S.y > 805 && S.y < 1020) {
        TX(&a, S, T_CPU, 150, 834, EM_N, M);
        var b: Buf; var n = 0;
        if (live) { n = fmt(&b, 0, s.cpu_total * 100.0, 0, 1); n = cat(&b, n, T_PCT); TB(&a, S, &b, n, 150, 954, EM_B, B); }
        seg_bar(&a, S, 150, 1001, 20, 30, 21, select(0.0, s.cpu_total, live), B);
        // per-cluster averages and the GPU beside the big number
        if (live && S.x > 540.0) {
            let nc = i32(min(s.cpu_count, 32u)); let ne = select(0, i32(s.cpu_e_cores), typed_cores());
            var pe = 0.0; var ee = 0.0;
            for (var i = 0; i < nc; i++) { if (i < ne) { ee += s.cpu_core[i]; } else { pe += s.cpu_core[i]; } }
            for (var r = 0; r < 3; r++) {
                let y = 894.0 + 30.0 * f32(r);
                if (abs(S.y - y + 8.0) > 22.0) { continue; }
                if (r == 2) { TX(&a, S, T_GPU, 555, y, EM_N, M); }
                else if (ne == 0) { if (r == 1) { continue; } TX(&a, S, T_CPU, 555, y, EM_N, M); }
                else if (r == 0) { TX(&a, S, T_PCL, 555, y, EM_N, M); } else { TX(&a, S, T_ECL, 555, y, EM_N, M); }
                let v = select(select(select(ee / f32(max(ne, 1)), pe / f32(max(nc - ne, 1)), r == 0), s.cpu_total, ne == 0), s.gpu_busy, r == 2);
                var p: Buf; var np = fmt(&p, 0, v * 100.0, 0, 1); np = cat(&p, np, T_PCT);
                TBR(&a, S, &p, np, 810.0, y, EM_N, B);
            }
        }
    }
    if (!live) { if (S.x > 850 && S.y > 150 && S.y < 250) { TX(&a, S, H_WAIT, CX0, 234, EM_N, B * blink); } return a; }
    let h = head_g(m.t_arr);
    let hi = m.hv; let lo = max(i32(s.seq) - 255, 1);
    let hh = min(i32(floor(h)) + 1, hi);
    // ---- CPU chart: a ring-buffer sweep, the head writes as the samples arrive
    if (S.x > 820 && S.y > 145 && S.y < 440) {
        TX(&a, S, T_CPUC, CX0, 174, EM_N, M);
        {   let pa = textureLoad(argus_state, vec2u(META_X + 5u, META_Y), 0);   // (peak, average) over the window
            var b: Buf; var n = cat(&b, 0, T_PEAK); n += fmt(&b, n, pa.x * 100.0, 0, 1); n = cat(&b, n, T_PCT);
            n = cat(&b, n, T_AVG); n += fmt(&b, n, pa.y * 100.0, 0, 1); n = cat(&b, n, T_PCT);
            TBR(&a, S, &b, n, CX1, 174, EM_N, M); }
        let bx = sd_box(S, vec2f(0.5 * (CX0 + CX1), 0.5 * (CPU_Y0 + CPU_Y1)), vec2f(0.5 * (CX1 - CX0), 0.5 * (CPU_Y1 - CPU_Y0)), 2.0);
        put_line(&a, abs(bx), 0.8, Dm);
        if (bx < 0.0) {
            if ((S.x - CX0) % ((CX1 - CX0) / 10.0) < 1.5 && S.y % 9.0 < 3.0) { put_fill(&a, -1.0, 0.16); }
            let gy = CPU_Y0 + 1.5 + 60.0 * mround((S.y - CPU_Y0 - 1.5) / 60.0);   // grid lines on whole scan lines
            if (abs(S.y - gy) < 0.5 && S.x % 8.0 < 3.0) { put_fill(&a, -1.0, 0.16); }
            let u = (S.x - CX0) / (CX1 - CX0);
            let age = col_age(u, h, CPU_N);
            let g = h - age;
            let dh = head_d(SER_CPU, S, h, CPU_N, CX0, CX1, CPU_Y0 + 2.0, CPU_Y1 - 2.0, 1.0, lo, hi);
            if (age < CPU_N - 2.4 && g >= f32(lo)) {
                let d = trace_d(SER_CPU, S, g, CPU_N, CX0, CX1, CPU_Y0 + 2.0, CPU_Y1 - 2.0, 1.0, lo, hh);
                put_line(&a, min(d, dh), 1.2, 0.72 + 0.5 * exp(-age / 1.5));
            } else { put_line(&a, dh, 1.2, 1.2); }
            TX(&a, S, T_FS100, CX0 + 15.0, 234, EM_N, Dm);
        }
    }
    // ---- network chart: RX solid, TX dashed, full scale follows the last minute
    if (S.x > 820 && S.y > 448 && S.y < 650) {
        TX(&a, S, T_NET, CX0, 474, EM_N, M);
        var b: Buf; var n = cat(&b, 0, T_RX); n = fmt_rate(&b, n, s.net_rx_bps); n = cat(&b, n, T_TX); n = fmt_rate(&b, n, s.net_tx_bps);
        TBR(&a, S, &b, n, CX1, 474, EM_N, B);
        let bx = sd_box(S, vec2f(0.5 * (CX0 + CX1), 0.5 * (NET_Y0 + NET_Y1)), vec2f(0.5 * (CX1 - CX0), 0.5 * (NET_Y1 - NET_Y0)), 2.0);
        put_line(&a, abs(bx), 0.8, Dm);
        {   var c: Buf; var nc = cat(&c, 0, T_FS); nc = fmt_rate(&c, nc, m.scale_net * 1e6); TB(&a, S, &c, nc, CX0 + 15.0, 534, EM_N, Dm); }
        if (bx < 0.0) {
            let u = (S.x - CX0) / (CX1 - CX0);
            let age = col_age(u, h, NET_N);
            let g = h - age;
            if (age >= NET_N - 1.2) { put_line(&a, head_d(SER_RX, S, h, NET_N, CX0, CX1, NET_Y0 + 2.0, NET_Y1 - 2.0, m.scale_net, lo, hi), 1.2, 1.2); }
            if (age < NET_N - 1.2 && g >= f32(lo)) {
                let fr = exp(-age / 1.5);
                put_line(&a, trace_d(SER_RX, S, g, NET_N, CX0, CX1, NET_Y0 + 2.0, NET_Y1 - 2.0, m.scale_net, lo, hh), 1.2, 0.7 + 0.5 * fr);
                {   // TX dashed: only the beam is blanked between dashes, so its glow stays continuous
                    let dt = trace_d(SER_TX, S, g, NET_N, CX0, CX1, NET_Y0 + 2.0, NET_Y1 - 2.0, m.scale_net, lo, hh);
                    let bt = 0.45 + 0.3 * fr;
                    a.x = max(a.x, bt * saturate(1.5 - dt) * select(0.0, 1.0, S.x % 10.0 < 6.0));
                    a.y = max(a.y, 0.6 * bt * exp(-max(dt - 1.0, 0.0) / 6.0));
                }
            }
        }
    }
    // ---- memory
    if (S.x > 820 && S.y > 655 && S.y < 790) {
        TX(&a, S, T_MEM, CX0, 684, EM_N, M);
        var b: Buf; var n = fmt(&b, 0, s.mem_used_gb, 1, 1); n = cat(&b, n, T_OF); n += fmt(&b, n, s.mem_total_gb, 1, 1); n = cat(&b, n, T_GB);
        TB(&a, S, &b, n, CX0 + 150.0, 684, EM_N, B);
        let nw = slen(press_word(s.mem_pressure));
        TXR(&a, S, T_PR, CX1 - tw(nw, EM_N), 684, EM_N, M);
        if (s.mem_pressure == 0u) { TXR(&a, S, press_word(0u), CX1, 684, EM_N, M); }
        else { let o = vec2f(CX1 - tw(nw, EM_N), 684); put_rev(&a, text_sd_c(S, o, EM_N, press_word(s.mem_pressure), nw, 0, 1.0), S, o, nw, EM_N, B * select(1.0, blink, s.mem_pressure > 1u)); }
        if (S.y > 702 && S.y < 732 && S.x > CX0 && S.x < CX1) {
            let cells = 40; let cw = (CX1 - CX0) / f32(cells);
            let cx = (S.x - CX0) / cw; let ci = i32(cx); let fx = cx - f32(ci);
            let gq = (f32(ci) + 0.5) / f32(cells) * max(s.mem_total_gb, 1.0);
            let app = max(s.mem_used_gb - s.mem_wired_gb - s.mem_compressed_gb, 0.0);
            if (fx > 0.12 && fx < 0.88) {
                if (gq < s.mem_wired_gb) { put_fill(&a, -1.0, 0.95); }
                else if (gq < s.mem_wired_gb + app) { put_fill(&a, -1.0, 0.6); }
                else if (gq < s.mem_used_gb) { if (floor(S.y / PITCH) % 2.0 < 1.0) { put_fill(&a, -1.0, 0.6); } }
                else { put_line(&a, min(min(fx - 0.12, 0.88 - fx) * cw, min(S.y - 702.0, 732.0 - S.y)), 0.7, 0.3); }
            }
        }
        if (S.y > 750.0 && S.y < 785.0) {
            var lw = array<vec2u, 4>(T_LW, T_LA, T_LC, T_LF);
            var x = CX0;
            for (var i = 0; i < 4; i++) {   // a swatch in one cell, then the word
                let sw = sd_box(S, vec2f(x + 7.5, 763.5), vec2f(5.0, 7.5), 0.0);
                if (i == 0) { put_fill(&a, sw, 0.95); } else if (i == 1) { put_fill(&a, sw, 0.6); }
                else if (i == 2) { if (floor(S.y / PITCH) % 2.0 < 1.0) { put_fill(&a, sw, 0.6); } } else { put_line(&a, abs(sw), 0.7, 0.3); }
                let n = slen(lw[i]); TBC(&a, S, lw[i], n, x + 30.0, 774.0, EM_N, Dm); x += tw(n + 4, EM_N);
            }
            var l: Buf; var nl = cat(&l, 0, T_SWAP); nl += fmt(&l, nl, s.swap_used_gb, 2, 1); nl = cat(&l, nl, T_GB);
            TBR(&a, S, &l, nl, CX1, 774, EM_N, Dm);
        }
    }
    // ---- processes (the user's own, highest CPU first); % CPU as Activity Monitor counts it (one core = 100)
    if (S.x > 820 && S.y > 800 && S.y < 1010) {
        TX(&a, S, T_PROC, CX0, 834, EM_N, M); TXR(&a, S, T_PCPU, 1335, 834, EM_N, M); TXR(&a, S, T_PMEM, 1515, 834, EM_N, M);
        for (var i = 0; i < i32(min(s.proc_count, 5u)); i++) {
            let y = 864.0 + 30.0 * f32(i);
            if (abs(S.y - y + 8.0) > 22.0) { continue; }
            let nm = u32(i);   // s.procs[i].name
            TBP(&a, S, nm, min(pname_len(nm), 18), CX0, y, EM_N, B * 0.9);
            let pc = s.procs[i].cpu * f32(s.cpu_count) * 100.0;
            var p: Buf; let np = fmt(&p, 0, pc, 1, 1); TBR(&a, S, &p, np, 1335, y, EM_N, B * 0.9);
            var q: Buf; let nq = fmt(&q, 0, s.procs[i].mem_gb, 2, 1); TBR(&a, S, &q, nq, 1515, y, EM_N, M);
            seg_bar(&a, S, 1545, y, 16, 15, 15, s.procs[i].cpu * 4.0, 0.8);   // full bar = a quarter of the machine
        }
    }
    // ---- footer: power, disk, thermal, uptime
    if (S.x > 120 && S.x < 1800) { put_line(&a, abs(S.y - 1035.0), 0.8, Dm); }
    if (S.y > 1043 && S.y < 1082) {
        var b: Buf; var n = 0;
        if (s.battery_present == 0u) { n = cat(&b, 0, T_AC); }
        else {
            n = cat(&b, 0, T_BATT); n += fmt(&b, n, s.battery_charge * 100.0, 0, 1); n = cat(&b, n, T_PCT);
            if (s.battery_charging != 0u) { n = cat(&b, n, T_CHG); }
            if (s.battery_minutes < 0.0) { n = cat(&b, n, T_CALC); }
            else if (s.battery_minutes > 0.0) {
                let mins = i32(s.battery_minutes); b[n] = 32u; n++; n += fmt(&b, n, f32(mins / 60), 0, 1); b[n] = 58u; n++; n = cat2(&b, n, mins % 60);   // ' ', ':'
                n = cat(&b, n, select(T_LEFT, T_TOFULL, s.battery_charging != 0u));
            } else if (s.on_ac != 0u) { b[n] = 32u; n++; b[n] = 65u; n++; b[n] = 67u; n++; }   // " AC"
        }
        let low = s.battery_present != 0u && s.on_ac == 0u && s.battery_charge < 0.2;
        if (low) { put_rev(&a, text_sd(S, vec2f(150, 1074), EM_N, &b, n, 0, 1.0), S, vec2f(150, 1074), n, EM_N, B * blink); }
        else { TB(&a, S, &b, n, 150, 1074, EM_N, M); }
        var d: Buf; var nd = cat(&d, 0, T_DISK); nd += fmt(&d, nd, s.disk_free_gb, 0, 1); nd = cat(&d, nd, T_FREE);
        TB(&a, S, &d, nd, 690, 1074, EM_N, M);
        TX(&a, S, T_TH, 1065, 1074, EM_N, M);
        let nt = slen(therm_word(s.thermal)); let to = vec2f(1065.0 + tw(8, EM_N), 1074.0);
        if (s.thermal == 0u) { put_text(&a, text_sd_c(S, to, EM_N, therm_word(0u), nt, 0, 1.0), EM_N, M); }
        else { put_rev(&a, text_sd_c(S, to, EM_N, therm_word(s.thermal), nt, 0, 1.0), S, to, nt, EM_N, B * select(1.0, blink, s.thermal > 1u)); }
        var u: Buf; var nu = cat(&u, 0, T_UP); let up = s.uptime_s;
        nu += fmt(&u, nu, f32(up / 86400u), 0, 1); nu = cat(&u, nu, T_D); nu = cat2(&u, nu, i32((up / 3600u) % 24u)); u[nu] = 58u; nu++; nu = cat2(&u, nu, i32((up / 60u) % 60u));
        TBR(&a, S, &u, nu, 1785, 1074, EM_N, M);
    }
    // ---- the log line, typed at 300 baud (30 characters a second), and the cursor
    if (S.y > 1080 && S.y < 1120 && S.x < 1800) {
        let len = i32(textureLoad(argus_state, vec2u(META_X, MSG_Y), 0).y);
        let t0 = floor(f.time / 10.0) * 10.0;
        let vis = min(len, i32((f.time - t0) * 30.0));
        var l: Buf; for (var i = 0; i < vis; i++) { l[i] = u32(i32(textureLoad(argus_state, vec2u(META_X + u32(i), MSG_Y), 0).x)); }
        TB(&a, S, &l, vis, 150, 1104, EM_N, M);
        let cx = 150.0 + tw(vis, EM_N) + 0.5 * ADV * EM_N;
        // the IBM PC's default cursor: an underline two scan lines tall, blinking once output stops
        if (vis < len || fract(f.time) < 0.5) { put_fill(&a, sd_box(S, vec2f(cx, 1107.0), vec2f(0.5 * ADV * EM_N - 1.0, 3.0), 0.0), B); }
    }
    return a;
}

// the log message for message slot mi (one every 10 s), composed once from the live sample
const L_SAMPLE = vec2u(373u, 9u);   // "> SAMPLE "
const L_RECV = vec2u(382u, 11u);   // " RECEIVED. "
const L_OK = vec2u(393u, 20u);   // "ALL SYSTEMS NOMINAL."
const L_PW = vec2u(413u, 16u);   // "MEMORY PRESSURE "
const L_THW = vec2u(429u, 14u);   // "THERMAL STATE "
const L_DOT = vec2u(443u, 1u);   // "."
const L_TOP = vec2u(444u, 15u);   // "> TOP PROCESS: "
const L_CPUP = vec2u(459u, 7u);   // "% CPU, "
const L_GBM = vec2u(466u, 4u);   // " GB."
const L_NET = vec2u(470u, 14u);   // "> NETWORK: RX "
const L_TX = vec2u(484u, 5u);   // ", TX "
const L_PWR = vec2u(489u, 9u);   // "> POWER: "
const L_DISK = vec2u(498u, 8u);   // "> DISK: "
const L_OFT = vec2u(506u, 12u);   // " GB FREE OF "
const L_UPT = vec2u(518u, 8u);   // " GB. UP "
const L_DAYS = vec2u(526u, 6u);   // " DAYS."
fn compose_msg(b: ptr<function, Buf>, mi: u32) -> i32 {
    var n = 0;
    // (Metal's case 1 falls through to case 2 when there are no processes; WGSL has no fallthrough.)
    var cs = mi % 5u;
    if (cs == 1u && s.proc_count == 0u) { cs = 2u; }
    switch (cs) {
    case 0u: {
        n = cat(b, 0, L_SAMPLE); n += fmt(b, n, f32(s.seq), 0, 6); n = cat(b, n, L_RECV);
        if (s.mem_pressure > 0u) { n = cat(b, n, L_PW); n = cat(b, n, press_word(s.mem_pressure)); n = cat(b, n, L_DOT); }
        else if (s.thermal > 0u) { n = cat(b, n, L_THW); n = cat(b, n, therm_word(s.thermal)); n = cat(b, n, L_DOT); }
        else { n = cat(b, n, L_OK); }
    }
    case 1u: {
        n = cat(b, 0, L_TOP); let k = min(pname_len(0u), 24);
        for (var i = 0; i < k; i++) { (*b)[n] = argus_proc_char(0u, u32(i)); n++; }
        (*b)[n] = 44u; n++; (*b)[n] = 32u; n++; n += fmt(b, n, s.procs[0].cpu * f32(s.cpu_count) * 100.0, 1, 1); n = cat(b, n, L_CPUP);   // ',' ' '
        n += fmt(b, n, s.procs[0].mem_gb, 2, 1); n = cat(b, n, L_GBM);
    }
    case 2u: { n = cat(b, 0, L_NET); n = fmt_rate(b, n, s.net_rx_bps); n = cat(b, n, L_TX); n = fmt_rate(b, n, s.net_tx_bps); n = cat(b, n, L_DOT); }
    case 3u: {
        n = cat(b, 0, L_PWR);
        if (s.battery_present == 0u) { n = cat(b, n, T_AC); }
        else {
            n = cat(b, n, T_BATT); n += fmt(b, n, s.battery_charge * 100.0, 0, 1); n = cat(b, n, T_PCT);
            if (s.battery_charging != 0u) { n = cat(b, n, T_CHG); } else if (s.on_ac != 0u) { (*b)[n] = 44u; n++; (*b)[n] = 32u; n++; n = cat(b, n, T_AC); }
        }
        n = cat(b, n, L_DOT); }
    default: {
        n = cat(b, 0, L_DISK); n += fmt(b, n, s.disk_free_gb, 0, 1); n = cat(b, n, L_OFT); n += fmt(b, n, s.disk_total_gb, 0, 1);
        n = cat(b, n, L_UPT); n += fmt(b, n, f32(s.uptime_s) / 86400.0, 1, 1); n = cat(b, n, L_DAYS); }
    }
    return min(n, 63);
}

// ---------------------------------------------------------------------------------- kernels
@compute @workgroup_size(16, 16)
fn argus_init(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    var v = vec4f(0.0);
    if (gid.y >= ATLAS_Y && gid.x < 1024u) { v = textureLoad(argus_data, vec2u(gid.x, gid.y - ATLAS_Y), 0); }
    if (gid.y == META_Y && gid.x == META_X) { v = vec4f(4095.0, 0.0, 0.0, 255.0); }
    if (gid.y == META_Y && gid.x == META_X + 3u) { v = vec4f(0.1, 0.0, 0.0, 0.0); }
    if (gid.y == META_Y && gid.x == META_X + 4u) { v = vec4f(-1.0, 0.0, 0.0, 0.0); }
    textureStore(argus_state_out, gid, v);
}

@compute @workgroup_size(16, 16)
fn argus_step(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    let m0 = textureLoad(argus_state, vec2u(META_X, META_Y), 0);
    let SEQM = 4194304u;   // seq kept as lo + 2048 hi (both exact in half floats), mod 2^22
    let prev = u32(m0.z) * 2048u + u32(m0.x);
    let none = m0.x > 4000.0;
    let fresh = s.seq > 0u && (none || (s.seq % SEQM) != prev);
    let delta = select(1u, (s.seq + SEQM - prev) % SEQM, fresh && !none);   // 1 unless samples were skipped
    let rt = select(min(m0.w + 1.0, 255.0), 0.0, fresh);   // ticks since the newest sample arrived
    var m: Meta;
    m.t_arr = select(join_time(textureLoad(argus_state, vec2u(META_X + 1u, META_Y), 0)), f.time, fresh);
    m.scale_net = max(textureLoad(argus_state, vec2u(META_X + 3u, META_Y), 0).x, 0.1);
    m.hv = select(i32(s.seq), i32(s.seq) - 1, fresh);
    var o = textureLoad(argus_state, gid, 0);
    if (gid.y < u32(LINES)) {
        // ---- a scan line: repaint (whole screen top to bottom over 4 ticks after a sample; animated
        // regions every tick), then the phosphor: what the beam writes now and the decaying ghost
        if (gid.x >= u32(VW)) { textureStore(argus_state_out, gid, vec4f(0.0)); return; }
        let S = vec2f(f32(gid.x) + 0.5, (f32(gid.y) + 0.5) * PITCH);
        // the repaint bands end in gaps of the layout, so no reading is torn between two ticks
        let band = select(select(select(3u, 2u, gid.y < 278u), 1u, gid.y < 215u), 0u, gid.y < 150u);
        var redo = f.frame < 3u || (rt < 4.0 && band == u32(rt)) || (s.seq == 0u && S.y > 150.0 && S.y < 250.0 && S.x > 820.0);
        if (!redo && s.seq > 0u) {
            if (S.y > 1080.0 && S.y < 1120.0) { redo = true; }                        // log line + cursor
            else if (S.y > 80.0 && S.y < 120.0 && S.x > 1100.0) { redo = true; }     // clock
            else if (S.x > CX0 - 2.0 && S.x < CX1 + 2.0 && ((S.y > CPU_Y0 - 2.0 && S.y < CPU_Y1 + 2.0) || (S.y > NET_Y0 - 2.0 && S.y < NET_Y1 + 2.0))) {
                let u = (S.x - CX0) / (CX1 - CX0);
                let N = select(NET_N, CPU_N, S.y < 450.0);
                let age = col_age(u, head_g(m.t_arr), N);
                redo = age < 3.0 || age > N - 3.0;                                    // around the head and its gap
            } else if ((S.y > 650.0 && S.y < 700.0 && S.x > 1500.0) || (S.y > 1043.0 && S.y < 1082.0 && S.x < 1500.0)) { redo = true; }  // blinking words
        }
        var c = o.xy; if (redo) { c = content(m, S); }
        let k1 = exp(-f.dt / TAU_FAST); let k2 = exp(-f.dt / TAU_TAIL);
        // o.z: fast ghost, o.w: slow tail (both of the sharp channel)
        let g1 = max((1.0 - TAIL) * c.x, o.z * k1); let g2 = max(TAIL * c.x, o.w * k2);
        textureStore(argus_state_out, gid, vec4f(c, g1, g2));
        return;
    }
    if (gid.y >= ATLAS_Y && gid.x < 1024u) { if (f.frame < 3u) { textureStore(argus_state_out, gid, o); } return; }
    if (gid.y >= HIST_Y && gid.y < HIST_Y + 4u && gid.x >= HIST_X && gid.x < HIST_X + 256u) {
        let j = gid.x - HIST_X;
        if (fresh && j == (s.seq & 255u)) {   // rates in MB/s; .y = 1: a recorded sample
            let sr = gid.y - HIST_Y;
            o.x = select(select(min(select(s.net_tx_bps, s.net_rx_bps, sr == SER_RX) * 1e-6, 6.0e4), s.gpu_busy, sr == SER_GPU), s.cpu_total, sr == SER_CPU);
            o.y = 1.0;
        } else if (fresh && delta > 1u && ((j + 256u - ((prev + 1u) & 255u)) & 255u) < min(delta - 1u, 256u)) { o.y = 0.0; }   // skipped
        textureStore(argus_state_out, gid, o);
        return;
    }
    if (gid.y == META_Y && gid.x >= META_X && gid.x < META_X + 48u) {
        let k = gid.x - META_X;
        if (k == 0u) { o = select(vec4f(m0.xyz, rt), vec4f(f32(s.seq % 2048u), 0.0, f32((s.seq / 2048u) % 2048u), rt), fresh); }
        else if (k == 1u) { o = select(o, split_time(f.time), fresh); }
        else if (k == 2u) { o = split_time(f.time); }
        else if (k == 3u) {
            if (fresh || f.frame < 3u) {   // full scale: the last minute's peak (and this sample), on a 1-2-5 ladder
                var pk = max(s.net_rx_bps, s.net_tx_bps) * 1e-6;
                for (var i = 1; i < 60; i++) { let g = i32(s.seq) - i; if (g < 1) { break; }
                    if (histv(SER_CPU, g).y < 0.5) { continue; }
                    pk = max(pk, max(hist(SER_RX, g), hist(SER_TX, g))); }
                var sc = 0.1;   // MB/s, 0.1 at least
                for (var i = 0; i < 30 && sc < pk * 1.05; i++) { let d = floor(log10(sc) + 1e-4); let mant = sc / pow(10.0, d); sc = select(select(10.0, 5.0, mant < 3.5), 2.0, mant < 1.5) * pow(10.0, d); }
                o.x = sc;
            }
        } else if (k == 4u) { o.x = floor(f.time / 10.0); }
        else if (k == 5u) {
            if (fresh || f.frame < 3u) {
                var pk = s.cpu_total; var sum = s.cpu_total; var cnt = 1;
                for (var i = 1; i < i32(CPU_N); i++) { let g = i32(s.seq) - i; if (g < 1) { break; }
                    let v = histv(SER_CPU, g); if (v.y < 0.5) { continue; } pk = max(pk, v.x); sum += v.x; cnt++; }
                o.x = pk; o.y = sum / f32(cnt);
            }
        }
        else if (k >= 8u && k < 8u + 33u) {
            // damped block level (x, v): critically damped toward the live value
            let i = i32(k - 8u); let n = i32(min(s.cpu_count, 32u));
            var T = 0.0; if (i < n) { T = s.cpu_core[i]; } else if (i == 32) { T = s.gpu_busy; }
            if (f.frame < 2u) { o = vec4f(T, 0.0, 0.0, 0.0); }
            else {
                let e = o.x - T; let v = o.y; let dt = f.dt; let ex = exp(-OMEGA * dt);
                o.x = T + (e + (v + OMEGA * e) * dt) * ex;
                o.y = (v - OMEGA * (v + OMEGA * e) * dt) * ex;
            }
        }
        textureStore(argus_state_out, gid, o);
        return;
    }
    if (gid.y == MSG_Y && gid.x >= META_X && gid.x < META_X + 64u) {
        let mi = u32(floor(f.time / 10.0));
        let last = textureLoad(argus_state, vec2u(META_X + 4u, META_Y), 0).x;
        if (f.frame < 3u || f32(mi) != last) {
            var b: Buf; var n = 0; if (s.seq > 0u) { n = compose_msg(&b, mi); }
            let i = i32(gid.x - META_X);
            o = vec4f(select(32.0, f32(i32(b[i])), i < n), f32(n), 0.0, 0.0);
        }
        textureStore(argus_state_out, gid, o);
        return;
    }
    textureStore(argus_state_out, gid, o);
}
// WGSL has no log10 (Metal's, used above for the 1-2-5 ladder).
fn log10(x: f32) -> f32 { return log2(x) * 0.30102999566398120; }

// ---------------------------------------------------------------------------------- draw: beam, glass, bezel
fn hammertone(P: vec2f, base: vec3f) -> vec3f {
    let n = argus_noise(P * 0.07) + 0.6 * argus_noise(P * 0.17 + 3.0) + 0.3 * argus_noise(P * 0.5);
    return base * (1.0 + 0.07 * n) + 0.012 * pow(saturate(n * 0.5 + 0.2), 4.0);
}
// live block fills (drawn per frame so the damped levels move smoothly at any frame rate)
fn block_fill(S: vec2f, tau: f32) -> f32 {
    if (s.seq == 0u || S.x < 160.0 || S.x > 720.0 || S.y < 190.0 || S.y > 600.0) { return 0.0; }
    let nb = i32(min(s.cpu_count, 32u)) + 1;
    for (var i = 0; i < nb; i++) {
        let k = block(i);
        let bd = sd_box(S, k.c, k.h, 3.0);
        if (bd > -2.0) { continue; }
        let xv = textureLoad(argus_state, vec2u(META_X + 8u + u32(select(32, i, i < nb - 1)), META_Y), 0);
        var T = s.gpu_busy; if (i < nb - 1) { T = s.cpu_core[i]; }
        let e = xv.x - T;
        let x = saturate(T + (e + (xv.y + OMEGA * e) * tau) * exp(-OMEGA * tau));
        let lby = gbase_at_or_below(k.c.y - k.h.y + 21.0);   // the label row stays clear: the fill's scale is the box below it
        let lb = select(lby + 5.0 - (k.c.y - k.h.y), 0.0, lby > k.c.y + k.h.y - 2.0);
        let lvl = k.c.y + k.h.y - (2.0 * k.h.y - lb) * x;
        let line = saturate(1.7 - abs(S.y - lvl));
        return max(line, select(0.0, 0.28 + 0.25 * x, S.y > lvl && bd < -4.0));
    }
    return 0.0;
}

@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let sc = min(f32(f.height) / VH, f32(f.width) / VW);   // the face fits any screen shape
    let P = (vec2f(gid) + 0.5 - 0.5 * vec2f(f32(f.width), f32(f.height))) / sc + 0.5 * vec2f(VW, VH);
    let q = (P - FACE_C) / FACE_H;
    let S = FACE_C + q * (1.0 + FACE_K * dot(q, q)) * FACE_H;
    let edge = sd_box(S, FACE_C, FACE_H, FACE_R);
    var col = vec3f(0.0);
    if (edge < 0.5) {
        // (Metal: constexpr sampler ls(filter::linear, address::clamp_to_edge), here argus_linear_clamp)
        let tau = wrap_dt(f.time - join_time(textureLoad(argus_state, vec2u(META_X + 2u, META_Y), 0)));
        let kf = floor(S.y / PITCH - 0.5);
        var I = 0.0; var G = 0.0;
        for (var j = 0; j < 2; j++) {
            let line = kf + f32(j);
            if (line < 0.0 || line >= f32(LINES)) { continue; }
            let yk = (line + 0.5) * PITCH;
            let t = argus_sample(argus_state, argus_linear_clamp, vec2f(S.x / f32(f.state_width), (line + 0.5) / f32(f.state_height)));
            var sharp = max(t.x, t.z + t.w);
            sharp = max(sharp, block_fill(vec2f(S.x, yk), tau));
            let sig = PITCH * (0.24 + 0.20 * saturate(sharp));   // the spot grows with beam current
            I += sharp * exp(-0.5 * sq((S.y - yk) / sig)) * 1.25;
            G += max(t.y, 0.5 * (t.z + t.w)) * (1.0 - abs(S.y - yk) / PITCH);
        }
        let E = I + 0.16 * G;
        // P39 / willemite x 0.21, y 0.71 lies outside sRGB; clipped per channel it is (0, 1, 0), the green a
        // monitor shows; a small floor of red and blue keeps faint strokes from going neon (CHOSEN)
        let ph = vec3f(0.04, 1.0, 0.07);
        col = vec3f(0.010, 0.013, 0.011) * (1.0 - 0.4 * dot(q, q));
        col += ph * E * 0.85 + vec3f(0.75, 1.0, 0.8) * max(E - 0.85, 0.0) * 0.5;
        let band = (f.time * 42.5) % 1700.0 - 250.0;   // CHOSEN: a faint rolling band (a film artefact)
        col *= 1.0 + 0.05 * exp(-sq((S.y - band) / 55.0));
        col *= (1.0 - 0.5 * pow(saturate(length(q) * 0.78), 4.0)) * (1.0 - 0.18 * sq(saturate(abs(q.x) * abs(q.y) * 1.1)));
        let rq = (q - vec2f(-0.50, -0.60)) / vec2f(0.45, 0.22);
        col += vec3f(0.026, 0.029, 0.032) * exp(-dot(rq, rq));
        col += vec3f(0.05) * exp(-sq((edge + 3.0) / 3.0)) * saturate(-q.y * 0.8 + 0.3);
    }
    if (edge > -0.5) {
        // painted steel with a fine orange-peel grain, lit from above; a 9 px chamfer down to the glass
        var b = vec3f(0.021, 0.023, 0.021) * (1.0 + 0.025 * argus_noise(P * 0.35) + 0.015 * argus_noise(P * 1.3));
        b *= 1.05 - 0.25 * P.y / VH;
        let nq = normalize(q + 1e-4);
        let lit = -nq.y;   // the lip facing up is lit, the one facing down in shadow
        let ch = saturate(1.0 - edge / 9.0);
        b *= 1.0 + ch * select(0.20, 0.12, lit > 0.0) * lit * 2.0 - 0.55 * exp(-max(edge, 0.0) / 3.0);
        b += vec3f(0.035) * exp(-sq((edge - 9.0) / 1.2)) * saturate(lit + 0.3);
        col = over(col, b, saturate(edge + 0.5));
    }
    col = 1.0 - exp(-col * 1.1);
    textureStore(argus_out, gid, vec4f(argus_srgb(col), 1.0));
}

// ---------------------------------------------------------------------------------- the string table
// Every constant string above (Metal's constant char arrays), concatenated as ASCII codes; each name is
// (start, length) into it.
const STR = array<u32, 532>(
    32, 75, 66, 47, 83,   // U_KBS
    32, 77, 66, 47, 83,   // U_MBS
    65, 82, 71, 85, 83, 32, 83, 89, 83, 84, 69, 77, 32, 77, 79, 78, 73, 84, 79, 82,   // H_TITLE
    83, 79, 67,   // H_SOC
    65, 87, 65, 73, 84, 73, 78, 71, 32, 84, 69, 76, 69, 77, 69, 84, 82, 89,   // H_WAIT
    71, 80, 85,   // T_GPU
    85, 78, 73, 70, 73, 69, 68, 32, 77, 69, 77, 79, 82, 89,   // T_UM
    32, 71, 66,   // T_GB
    67, 80, 85, 32, 76, 79, 65, 68,   // T_CPU
    67, 80, 85, 32, 32, 49, 50, 48, 32, 83,   // T_CPUC
    80, 69, 65, 75, 32,   // T_PEAK
    32, 32, 65, 86, 71, 32,   // T_AVG
    70, 85, 76, 76, 32, 83, 67, 65, 76, 69, 32, 49, 48, 48, 37,   // T_FS100
    80, 32, 67, 76, 85, 83, 84, 69, 82,   // T_PCL
    69, 32, 67, 76, 85, 83, 84, 69, 82,   // T_ECL
    76, 80, 68, 68, 82,   // T_LPDDR
    78, 69, 84, 87, 79, 82, 75, 32, 32, 54, 48, 32, 83,   // T_NET
    82, 88, 32,   // T_RX
    32, 32, 32, 84, 88, 32,   // T_TX
    70, 85, 76, 76, 32, 83, 67, 65, 76, 69, 32,   // T_FS
    77, 69, 77, 79, 82, 89,   // T_MEM
    32, 47, 32,   // T_OF
    80, 82, 69, 83, 83, 85, 82, 69, 32,   // T_PR
    78, 79, 82, 77, 65, 76,   // T_PRS0
    87, 65, 82, 78,   // T_PRS1
    67, 82, 73, 84, 73, 67, 65, 76,   // T_PRS2
    87, 73, 82, 69, 68,   // T_LW
    65, 80, 80,   // T_LA
    67, 79, 77, 80, 82, 69, 83, 83, 69, 68,   // T_LC
    70, 82, 69, 69,   // T_LF
    83, 87, 65, 80, 32,   // T_SWAP
    80, 82, 79, 67, 69, 83, 83,   // T_PROC
    37, 32, 67, 80, 85,   // T_PCPU
    77, 69, 77, 32, 71, 66,   // T_PMEM
    37,   // T_PCT
    66, 65, 84, 84, 32,   // T_BATT
    65, 67, 32, 80, 79, 87, 69, 82,   // T_AC
    32, 67, 72, 65, 82, 71, 73, 78, 71,   // T_CHG
    32, 76, 69, 70, 84,   // T_LEFT
    32, 67, 65, 76, 67, 85, 76, 65, 84, 73, 78, 71,   // T_CALC
    32, 84, 79, 32, 70, 85, 76, 76,   // T_TOFULL
    68, 73, 83, 75, 32,   // T_DISK
    32, 71, 66, 32, 70, 82, 69, 69,   // T_FREE
    84, 72, 69, 82, 77, 65, 76, 32,   // T_TH
    78, 79, 77, 73, 78, 65, 76,   // T_TH0
    70, 65, 73, 82,   // T_TH1
    83, 69, 82, 73, 79, 85, 83,   // T_TH2
    67, 82, 73, 84, 73, 67, 65, 76,   // T_TH3
    85, 80, 32,   // T_UP
    68, 32,   // T_D
    83, 85, 78, 77, 79, 78, 84, 85, 69, 87, 69, 68, 84, 72, 85, 70, 82, 73, 83, 65, 84,   // DAYS
    62, 32, 83, 65, 77, 80, 76, 69, 32,   // L_SAMPLE
    32, 82, 69, 67, 69, 73, 86, 69, 68, 46, 32,   // L_RECV
    65, 76, 76, 32, 83, 89, 83, 84, 69, 77, 83, 32, 78, 79, 77, 73, 78, 65, 76, 46,   // L_OK
    77, 69, 77, 79, 82, 89, 32, 80, 82, 69, 83, 83, 85, 82, 69, 32,   // L_PW
    84, 72, 69, 82, 77, 65, 76, 32, 83, 84, 65, 84, 69, 32,   // L_THW
    46,   // L_DOT
    62, 32, 84, 79, 80, 32, 80, 82, 79, 67, 69, 83, 83, 58, 32,   // L_TOP
    37, 32, 67, 80, 85, 44, 32,   // L_CPUP
    32, 71, 66, 46,   // L_GBM
    62, 32, 78, 69, 84, 87, 79, 82, 75, 58, 32, 82, 88, 32,   // L_NET
    44, 32, 84, 88, 32,   // L_TX
    62, 32, 80, 79, 87, 69, 82, 58, 32,   // L_PWR
    62, 32, 68, 73, 83, 75, 58, 32,   // L_DISK
    32, 71, 66, 32, 70, 82, 69, 69, 32, 79, 70, 32,   // L_OFT
    32, 71, 66, 46, 32, 85, 80, 32,   // L_UPT
    32, 68, 65, 89, 83, 46,   // L_DAYS
);
