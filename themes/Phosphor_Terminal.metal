// PHOSPHOR TERMINAL // themes/Phosphor_Terminal.metal
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
constant float VW = 1920.0f;           // virtual canvas: 1920 x 1200, scaled to the screen height
constant float VH = 1200.0f;
constant int   LINES = 400;            // scan lines on the face
constant float PITCH = 3.0f;           // virtual px per scan line
constant uint  ATLAS_Y = 400;          // glyph atlas rows in the state
constant uint  HIST_X = 1024, HIST_Y = 400;   // history rings: 256 samples per series, one row each
constant uint  META_X = 1024, META_Y = 420;   // bookkeeping texels
constant uint  MSG_Y = 421;                   // the log message, one character per texel
constant float CELL = 64.0f, SPREAD = 8.0f, EMPX = 50.0f, FBASE = 0.75f;   // atlas: 50 px per em, baseline at 48
constant float ADV = 0.4f;             // VT323 advance, em: a 15 x 30 px cell at 37.5 px per em
constant float2 FACE_C = float2(960.0f, 600.0f), FACE_H = float2(905.0f, 565.0f);
constant float FACE_R = 80.0f, FACE_K = 0.025f;
// text sizes (em, virtual px): cap height = 0.698 em lands on whole scan lines
// VT323 draws on a dot grid: 80 font units a dot row, caps 7 rows. At 37.5 px per em one dot row is one scan
// line (3 px), so the character cell is 15 x 30 px (10 lines): 128 columns x 40 rows. Text sits on that grid
// (baseline of row r at y = 30 r + 24); the big readout is the same glyphs at 5x.
constant float EM_N = 37.5f, EM_B = 187.5f;
static inline float gx(float x) { return 15.0f * round(x / 15.0f); }
static inline float gbase_at_or_below(float ytop) { return 30.0f * ceil((ytop - 3.0f) / 30.0f) + 24.0f; }
// phosphor: P39 (Zn2SiO4:Mn,As) falls to ~10 % in ~150 ms; a small slow tail
constant float TAU_FAST = 0.065f, TAU_TAIL = 0.8f, TAIL = 0.008f;
constant float OMEGA = 10.0f;          // block levels: critically damped, 99 % in ~0.66 s
// series in the history rings
constant uint SER_CPU = 0, SER_GPU = 1, SER_RX = 2, SER_TX = 3;
constant float CPU_N = 120.0f, NET_N = 60.0f;   // samples across each chart

static inline float sq(float x) { return x * x; }
static inline float sd_box(float2 p, float2 c, float2 hw, float r) {
    const float2 q = abs(p - c) - hw + r;
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - r;
}
static inline float3 over(float3 c, float3 x, float a) { return mix(c, x, saturate(a)); }
static inline float wrap_dt(float d) { return d < -1.0f ? d + ARGUS_TIME_PERIOD : max(d, 0.0f); }
static inline float4 split_time(float t) { const float a = floor(t / 1024.0f); const float b = floor(t - a * 1024.0f); return float4(a, b, t - a * 1024.0f - b, 0.0f); }
static inline float join_time(float4 v) { return v.x * 1024.0f + v.y + v.z; }

// ---------------------------------------------------------------------------------- text
typedef texture2d<float, access::read> RTex;
// signed distance (atlas px, + inside) of glyph c at q (atlas px in its cell, y down); manual bilinear
static float glyph_sd(RTex pv, int c, int font, float2 q) {
    const int g = clamp(c - 32, 0, 95);
    q = clamp(q, 0.5f, CELL - 0.5f) - 0.5f;
    const float2 o = float2(g & 15, g >> 4) * CELL + float2(0.0f, float(ATLAS_Y));
    const float2 i = floor(q), w = q - i;
    const uint2 p = uint2(o + i);
    const uint2 p1 = min(p + 1u, uint2(pv.get_width() - 1, pv.get_height() - 1)); // the (0-weight) far taps stay inside
    const float4 a = pv.read(p), b = pv.read(uint2(p1.x, p.y)), c2 = pv.read(uint2(p.x, p1.y)), d = pv.read(p1);
    const float4 v = mix(mix(a, b, w.x), mix(c2, d, w.x), w.y);
    return ((font == 0 ? v.x : v.y) - 0.5f) * 2.0f * SPREAD;
}
// monospace string, baseline-left at org, em size em: signed distance in virtual px (+ inside)
template <typename S>
static float text_sd(RTex pv, float2 p, float2 org, float em, S s, int n, int font, float xs = 1.0f) {
    const float adv = ADV * em * xs, sc = em / EMPX;
    const float2 q = p - org;
    if (q.y < -0.9f * em || q.y > 0.35f * em || q.x < -0.5f * adv || q.x > (float(n) + 0.5f) * adv) return -1e3f;
    const int i0 = int(floor(q.x / adv));
    float best = -1e3f;
    for (int j = -1; j <= 1; ++j) {
        const int i = i0 + j;
        if (i < 0 || i >= n) continue;
        const int c = int(s[i]);
        if (c <= 32) continue;
        best = max(best, glyph_sd(pv, c, font, float2((q.x - float(i) * adv) / (sc * xs) + SPREAD, q.y / sc + FBASE * CELL)));
    }
    return best * sc;
}
static inline float tw(int n, float em) { return float(n) * ADV * em; }
static int slen(constant char* s) { int n = 0; while (s[n] != 0 && n < 63) ++n; return n; }
static int pname_len(constant uchar* s) { int n = 0; while (n < 31 && s[n] != 0) ++n; return n; }
static int fmt(thread char* b, float v, int dec, int minint) {
    float m = 1.0f; for (int i = 0; i < dec; ++i) m *= 10.0f;
    const int x = int(floor(max(v, 0.0f) * m + 0.5f));
    thread char t[14]; int nd = 0;
    int ip = x; for (int i = 0; i < dec; ++i) ip /= 10;
    int fp = x - ip * int(m);
    for (int i = 0; i < dec; ++i) { t[nd++] = char('0' + fp % 10); fp /= 10; }
    if (dec > 0) t[nd++] = '.';
    int k = 0; do { t[nd++] = char('0' + ip % 10); ip /= 10; ++k; } while ((ip > 0 || k < minint) && nd < 13);
    for (int i = 0; i < nd; ++i) b[i] = t[nd - 1 - i];
    return nd;
}
static int cat(thread char* b, int n, constant char* s) { int i = 0; while (s[i] != 0 && n < 63) b[n++] = s[i++]; return n; }
static int catb(thread char* b, int n, thread const char* s, int m) { for (int i = 0; i < m && n < 63; ++i) b[n++] = s[i]; return n; }
static int cat2(thread char* b, int n, int v) { b[n++] = char('0' + (v / 10) % 10); b[n++] = char('0' + v % 10); return n; }
// a rate in bytes/s as "840 KB/S" or "2.4 MB/S"
constant char U_KBS[] = " KB/S"; constant char U_MBS[] = " MB/S";
static int fmt_rate(thread char* b, int n, float bps) {
    if (bps < 1e6f) { n += fmt(b + n, bps / 1e3f, bps < 1e4f ? 1 : 0, 1); return cat(b, n, U_KBS); }
    n += fmt(b + n, bps / 1e6f, bps < 1e7f ? 1 : 0, 1); return cat(b, n, U_MBS);
}

// ---------------------------------------------------------------------------------- the machine's blocks
struct Blk { float2 c; float2 h; };
static Blk grid_block(int i, int n, float2 lo, float2 hi) {
    const float2 sz = hi - lo;
    const int cols = clamp(int(round(sqrt(float(n) * sz.x / sz.y))), 1, max(n, 1));
    const int rows = (n + cols - 1) / cols;
    const float2 cell = sz / float2(cols, rows);
    Blk b; b.c = lo + (float2(i % cols, i / cols) + 0.5f) * cell; b.h = 0.5f * cell - 7.0f;
    return b;
}
static bool typed_cores(constant ArgusStats& s) { return s.cpu_p_cores + s.cpu_e_cores == s.cpu_count && s.cpu_p_cores > 0; }
// block i: 0..count-1 the cores in the kernel's order (efficiency first), count = the GPU
static Blk block(int i, constant ArgusStats& s) {
    const int n = int(min(s.cpu_count, 32u));
    if (i >= n) { Blk g; g.c = float2(590.0f, 356.0f); g.h = float2(120.0f, 106.0f); return g; }
    if (!typed_cores(s)) return grid_block(i, n, float2(185, 245), float2(450, 560));
    const int e = int(s.cpu_e_cores);
    const float eh = e <= 4 ? 75.0f : 110.0f;
    if (i < e) return grid_block(i, e, float2(185.0f, 560.0f - eh), float2(450, 560));
    return grid_block(i - e, n - e, float2(185, 245), float2(450.0f, 545.0f - eh));
}
static int block_label(thread char* b, int i, constant ArgusStats& s) {
    const int n = int(min(s.cpu_count, 32u)); int k = 0;
    if (i >= n) { b[0] = 'G'; b[1] = 'P'; b[2] = 'U'; return 3; }
    if (!typed_cores(s)) { b[k++] = 'C'; }
    else if (i < int(s.cpu_e_cores)) { b[k++] = 'E'; }
    else { b[k++] = 'P'; i -= int(s.cpu_e_cores); }
    return k + fmt(b + k, float(i + 1), 0, 1);
}

// ---------------------------------------------------------------------------------- content: what the beam writes
struct Meta {
    float t_arr;      // f.time when the newest sample arrived
    float scale_net;  // network chart full scale, MB/s
    int hv;           // newest sample already in the history rings (the newest one lands a tick later)
};
static float2 histv(RTex pv, uint ser, int g) { return pv.read(uint2(HIST_X + uint(g & 255), HIST_Y + ser)).xy; }
static float hist(RTex pv, uint ser, int g) { return histv(pv, ser, g).x; }
static bool hok(RTex pv, int g, int lo, int hi) { return g >= lo && g <= hi && histv(pv, SER_CPU, g).y > 0.5f; }
// monotone cubic (Fritsch-Butland) through the samples around global sample coordinate g (clamped to [lo, hi])
static float hist_at(RTex pv, uint ser, float g, int lo, int hi) {
    const float gf = floor(g); const float t = g - gf; const int i = int(gf);
    const float p1 = hist(pv, ser, clamp(i, lo, hi));
    const float p2 = hok(pv, i + 1, lo, hi) ? hist(pv, ser, i + 1) : p1;
    const float p0 = hok(pv, i - 1, lo, hi) ? hist(pv, ser, i - 1) : p1;
    const float p3 = hok(pv, i + 2, lo, hi) ? hist(pv, ser, i + 2) : p2;
    const float d0 = p1 - p0, d1 = p2 - p1, d2 = p3 - p2;
    const float m1 = d0 * d1 > 0.0f ? 2.0f * d0 * d1 / (d0 + d1) : 0.0f;
    const float m2 = d1 * d2 > 0.0f ? 2.0f * d1 * d2 / (d1 + d2) : 0.0f;
    const float t2 = t * t, t3 = t2 * t;
    return (2.0f * t3 - 3.0f * t2 + 1.0f) * p1 + (t3 - 2.0f * t2 + t) * m1 + (-2.0f * t3 + 3.0f * t2) * p2 + (t3 - t2) * m2;
}
static inline float seg_d(float2 p, float2 a, float2 b) {
    const float2 pa = p - a, ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6f)));
}
// distance from S to the trace of series ser drawn over a chart (x0..x1, y0..y1), sample coordinate g at S.x,
// N samples across, value / div mapped to the height; a 7-point polyline around the column
static float trace_d(RTex pv, uint ser, float2 S, float g, float N, float x0, float x1, float y0, float y1, float div, int lo, int hi) {
    const float gpx = N / (x1 - x0);   // samples per px
    float d = 1e3f; float2 prev = float2(0.0f); bool okp = false;
    for (int k = -3; k <= 3; ++k) {
        const float dx = float(k) * 2.0f;
        const float gk = clamp(g + dx * gpx, float(lo), float(hi));
        const int gi = int(floor(gk));
        const bool ok = hok(pv, gi, lo, hi) && (gk == float(gi) || hok(pv, gi + 1, lo, hi));
        const float2 pk = float2(S.x + dx, y1 - (y1 - y0) * saturate(hist_at(pv, ser, gk, lo, hi) / div));
        if (k > -3 && ok && okp) d = min(d, seg_d(S, prev, pk));
        prev = pk; okp = ok;
    }
    return d;
}
// distance to the write head's spot (the newest point of the trace), so the trace ends in a round glow
static float head_d(RTex pv, uint ser, float2 S, float h, float N, float x0, float x1, float y0, float y1, float div, int lo, int hi) {
    const float xh = x0 + (x1 - x0) * fract(h / N);
    const float yh = y1 - (y1 - y0) * saturate(hist_at(pv, ser, clamp(h, float(lo), float(hi)), lo, hi) / div);
    return length(S - float2(xh, yh));
}
static void put_text(thread float2& a, float sd, float em, float b) {
    a.x = max(a.x, b * saturate(sd + 0.5f));
    const float sp = SPREAD * em / EMPX;
    a.y = max(a.y, b * (em < 25.0f ? 0.55f : 1.0f) * exp(min(sd, 0.0f) / 5.0f) * saturate((sd + 0.85f * sp) / (0.25f * sp)));
}
static void put_rev(thread float2& a, float sd, float2 S, float2 org, int n, float em, float b) {
    // reverse video: a lit cell box with the glyph cut out of it
    const float box = sd_box(S, org + float2(0.5f * tw(n, em), -9.0f), float2(0.5f * tw(n, em), 15.0f), 0.0f);   // the cells
    const float v = b * saturate(0.5f - box) * (1.0f - saturate(sd + 0.5f));
    a.x = max(a.x, v); a.y = max(a.y, b * saturate(0.5f - box) * 0.6f);
}
static void put_line(thread float2& a, float d, float w, float b) {
    a.x = max(a.x, b * saturate(w + 0.5f - d));
    a.y = max(a.y, b * exp(-max(d - w, 0.0f) / 4.5f));
}
static void put_fill(thread float2& a, float sd, float b) {
    a.x = max(a.x, b * saturate(0.5f - sd));
    a.y = max(a.y, b * exp(-max(sd, 0.0f) / 6.0f));
}
static void seg_bar(thread float2& a, float2 S, float x0, float y0, int cells, float cw, float h, float v, float b) {
    if (S.y < y0 - h || S.y > y0 || S.x < x0 || S.x > x0 + float(cells) * cw) return;
    const float cx = (S.x - x0) / cw; const int ci = int(cx); const float fx = cx - float(ci);
    if (fx > 0.14f && fx < 0.86f) {
        if (float(ci) + 0.5f < v * float(cells)) put_fill(a, -1.0f, b);
        else put_line(a, min(min(fx - 0.14f, 0.86f - fx) * cw, min(S.y - (y0 - h), y0 - S.y)), 0.7f, b * 0.30f);
    }
}
#define TX(str, x, y, em, b) put_text(a, text_sd(pv, S, float2(x, y), em, str, slen(str), 0), em, b)
#define TXR(str, x, y, em, b) { const int _n = slen(str); put_text(a, text_sd(pv, S, float2((x) - tw(_n, em), y), em, str, _n, 0), em, b); }
#define TB(buf, n, x, y, em, b) put_text(a, text_sd(pv, S, float2(x, y), em, buf, n, 0), em, b)
#define TBR(buf, n, x, y, em, b) put_text(a, text_sd(pv, S, float2((x) - tw(n, em), y), em, buf, n, 0), em, b)

constant char H_TITLE[] = "ARGUS SYSTEM MONITOR"; constant char H_SOC[] = "SOC";
constant char H_WAIT[] = "AWAITING TELEMETRY";
constant char T_GPU[] = "GPU"; constant char T_UM[] = "UNIFIED MEMORY"; constant char T_GB[] = " GB";
constant char T_CPU[] = "CPU LOAD"; constant char T_CPUC[] = "CPU  120 S"; constant char T_PEAK[] = "PEAK "; constant char T_AVG[] = "  AVG ";
constant char T_FS100[] = "FULL SCALE 100%"; constant char T_PCL[] = "P CLUSTER"; constant char T_ECL[] = "E CLUSTER"; constant char T_LPDDR[] = "LPDDR"; constant char T_NET[] = "NETWORK  60 S";
constant char T_RX[] = "RX "; constant char T_TX[] = "   TX "; constant char T_FS[] = "FULL SCALE ";
constant char T_MEM[] = "MEMORY"; constant char T_OF[] = " / "; constant char T_PR[] = "PRESSURE ";
constant char T_PRS0[] = "NORMAL"; constant char T_PRS1[] = "WARN"; constant char T_PRS2[] = "CRITICAL";
constant char T_LW[] = "WIRED"; constant char T_LA[] = "APP"; constant char T_LC[] = "COMPRESSED"; constant char T_LF[] = "FREE"; constant char T_SWAP[] = "SWAP "; constant char T_PROC[] = "PROCESS";
constant char T_PCPU[] = "% CPU"; constant char T_PMEM[] = "MEM GB"; constant char T_PCT[] = "%";
constant char T_BATT[] = "BATT "; constant char T_AC[] = "AC POWER"; constant char T_CHG[] = " CHARGING";
constant char T_LEFT[] = " LEFT"; constant char T_CALC[] = " CALCULATING"; constant char T_TOFULL[] = " TO FULL";
constant char T_DISK[] = "DISK "; constant char T_FREE[] = " GB FREE"; constant char T_TH[] = "THERMAL ";
constant char T_TH0[] = "NOMINAL"; constant char T_TH1[] = "FAIR"; constant char T_TH2[] = "SERIOUS"; constant char T_TH3[] = "CRITICAL";
constant char T_UP[] = "UP "; constant char T_D[] = "D ";
constant char DAYS[] = "SUNMONTUEWEDTHUFRISAT";
static constant char* press_word(uint p) { return p == 0 ? T_PRS0 : p == 1 ? T_PRS1 : T_PRS2; }
static constant char* therm_word(uint t) { return t == 0 ? T_TH0 : t == 1 ? T_TH1 : t == 2 ? T_TH2 : T_TH3; }

// local civil date and time from the ArgusFrame clock
static int fmt_datetime(thread char* b, constant ArgusFrame& f) {
    const float loc = argus_utc_seconds(f) + float(f.utc_offset_s);
    const int dshift = int(floor(loc / 86400.0f));
    const float sec = loc - float(dshift) * 86400.0f;
    // days_j2000 counts from noon; day_frac >= 0.5 means past midnight UTC of the next civil day
    const int jdn = 2451545 + f.days_j2000 + (f.day_frac >= 0.5f ? 1 : 0) + dshift;
    int l = jdn + 68569; const int nn = 4 * l / 146097; l = l - (146097 * nn + 3) / 4;
    const int ii = 4000 * (l + 1) / 1461001; l = l - 1461 * ii / 4 + 31;
    const int jj = 80 * l / 2447; const int day = l - 2447 * jj / 80; l = jj / 11;
    const int mon = jj + 2 - 12 * l; const int yr = 100 * (nn - 49) + ii + l;
    const int wd = (jdn + 1) % 7;
    int n = 0;
    for (int i = 0; i < 3; ++i) b[n++] = DAYS[wd * 3 + i];
    b[n++] = ' '; n += fmt(b + n, float(yr), 0, 4); b[n++] = '-'; n = cat2(b, n, mon); b[n++] = '-'; n = cat2(b, n, day);
    b[n++] = ' '; b[n++] = ' ';
    const int si = int(sec);
    n = cat2(b, n, si / 3600); b[n++] = ':'; n = cat2(b, n, (si / 60) % 60); b[n++] = ':'; n = cat2(b, n, si % 60);
    return n;
}

// chart geometry
constant float CX0 = 855.0f, CX1 = 1785.0f;
constant float CPU_Y0 = 186.0f, CPU_Y1 = 426.0f, NET_Y0 = 486.0f, NET_Y1 = 636.0f;
// where the write head is, in samples: one sample behind the newest, advancing continuously
static float head_g(constant ArgusStats& s, constant ArgusFrame& f, float t_arr) {
    const float ph = saturate(wrap_dt(f.time - t_arr) / max(s.sample_dt, 0.25f));
    return float(s.seq) - 1.0f + ph;
}
// age (samples behind the head) of the column at u in a chart of N samples
static float col_age(float u, float h, float N) { return fmod(h - u * N + 4.0f * N, N); }

static float2 content(RTex pv, constant ArgusFrame& f, constant ArgusStats& s, thread const Meta& m, float2 S) {
    float2 a = float2(0.0f);
    const float B = 1.0f, M = 0.42f, Dm = 0.24f;
    const bool live = s.seq > 0;
    const float blink = fract(f.time) < 0.6f ? 1.0f : 0.0f;   // attribute blink, ~1 Hz (CHOSEN)
    // ---- header: the line steps up around the title, like a tab
    put_text(a, text_sd(pv, S, float2(150, 114), EM_N, H_TITLE, slen(H_TITLE), 0, 2.0f), EM_N, B);   // double width
    if (S.y > 80 && S.y < 120 && S.x > 1100) { thread char b[32]; const int n = fmt_datetime(b, f); TBR(b, n, 1785, 114, EM_N, M); }
    if (S.x > 120 && S.x < 1800 && S.y > 70 && S.y < 140) {
        const float gx0 = 138.0f, gx1 = 162.0f + 2.0f * tw(20, EM_N);
        if (S.x < gx0 || S.x > gx1) put_line(a, abs(S.y - 130.5f), 1.0f, M); else put_line(a, abs(S.y - 76.5f), 1.0f, M * 0.8f);
        put_line(a, length(float2(min(abs(S.x - gx0), abs(S.x - gx1)), max(abs(S.y - 103.5f) - 27.0f, 0.0f))), 1.0f, M * 0.8f);
    }
    // ---- the machine as a schematic: package, pins, one block per core, the GPU, unified memory
    if (S.x < 800 && S.y > 150 && S.y < 800) {
        // package (a pin-1 mark in its corner), the die inside it, two memory packages beside the die
        const float co = sd_box(S, float2(445, 475), float2(300, 290), 14.0f);
        put_line(a, abs(co), 1.2f, M);
        if (co < -3.0f && (S.x - 145.0f) + (S.y - 185.0f) < 34.0f) put_fill(a, -1.0f, Dm);
        put_line(a, abs(sd_box(S, float2(447, 400), float2(275, 172), 6.0f)), 0.8f, Dm);
        {   // "SOC  6P+4E  16 GB"
            thread char b[32]; int n = cat(b, 0, H_SOC); b[n++] = ' '; b[n++] = ' ';
            if (typed_cores(s)) { n += fmt(b + n, float(s.cpu_p_cores), 0, 1); b[n++] = 'P'; b[n++] = '+'; n += fmt(b + n, float(s.cpu_e_cores), 0, 1); b[n++] = 'E'; }
            else { n += fmt(b + n, float(s.cpu_count), 0, 1); b[n++] = 'C'; }
            b[n++] = ' '; b[n++] = ' '; n += fmt(b + n, s.mem_total_gb, 0, 1); n = cat(b, n, T_GB);
            if (live) TB(b, n, 150, 174, EM_N, Dm);
        }
        const int nb = int(min(s.cpu_count, 32u)) + 1;
        for (int i = 0; i < nb; ++i) {
            const Blk k = block(i, s);
            if (abs(S.x - k.c.x) > k.h.x + 10.0f || abs(S.y - k.c.y) > k.h.y + 30.0f) continue;
            put_line(a, abs(sd_box(S, k.c, k.h, 3.0f)), 1.0f, M);
            thread char b[8]; const int n = block_label(b, i, s);
            const float lby = gbase_at_or_below(k.c.y - k.h.y + 21.0f);   // the first grid row inside the block
            if (lby > k.c.y + k.h.y - 2.0f) continue;
            if (k.h.x >= 40.0f) {
                TB(b, n, 15.0f * ceil((k.c.x - k.h.x + 5.0f) / 15.0f), lby, EM_N, B);
                thread char p[8]; const float v = i < nb - 1 ? s.cpu_core[i] : s.gpu_busy;
                int np = fmt(p, v * 100.0f, 0, 1); np = cat(p, np, T_PCT);
                if (live) TBR(p, np, 15.0f * floor((k.c.x + k.h.x - 4.0f) / 15.0f), lby, EM_N, M);
            } else if (k.h.x >= 0.5f * tw(n, EM_N) + 2.0f) TB(b, n, gx(k.c.x - 0.5f * tw(n, EM_N)), lby, EM_N, M);
        }
        // unified memory in two packages: wired | app | compressed fill from the left, free left open
        if (S.y > 595.0f && S.y < 750.0f) {
            const float tot = max(s.mem_total_gb, 1.0f);
            const float app = max(s.mem_used_gb - s.mem_wired_gb - s.mem_compressed_gb, 0.0f);
            for (int pk = 0; pk < 2; ++pk) {
                const float2 mc = float2(pk == 0 ? 307.0f : 587.0f, 672.0f), mh = float2(130.0f, 64.0f);
                const float md = sd_box(S, mc, mh, 3.0f);
                if (md > 8.0f) continue;
                put_line(a, abs(md), 1.0f, M);
                const float u = (float(pk) + (S.x - (mc.x - mh.x)) / (2.0f * mh.x)) * 0.5f * tot;
                if (live && md < -4.0f && S.y > mc.y - 6.0f) {
                    if (u < s.mem_wired_gb) put_fill(a, -1.0f, 0.75f);
                    else if (u < s.mem_wired_gb + app) put_fill(a, -1.0f, 0.45f);
                    else if (u < s.mem_used_gb) { if (fmod(floor(S.y / PITCH), 2.0f) < 1.0f) put_fill(a, -1.0f, 0.45f); }
                }
                thread char b[24]; int n = cat(b, 0, T_LPDDR); b[n++] = ' '; b[n++] = ' '; n += fmt(b + n, 0.5f * s.mem_total_gb, 0, 1); n = cat(b, n, T_GB);
                TB(b, n, 15.0f * ceil((mc.x - mh.x + 6.0f) / 15.0f), 654.0f, EM_N, M);
                const int ng = clamp(int(0.5f * tot), 1, 96);
                const float gx = (S.x - (mc.x - mh.x)) / (2.0f * mh.x) * float(ng);
                if (ng <= 32 && abs(S.y - (mc.y + 30.0f)) < 30.0f) put_line(a, abs(gx - round(gx)) * 2.0f * mh.x / float(ng), 0.6f, Dm * step(0.5f, gx) * step(gx, float(ng) - 0.5f));
            }
        }
    }
    // ---- big CPU readout
    if (S.x < 840 && S.y > 805 && S.y < 1020) {
        TX(T_CPU, 150, 834, EM_N, M);
        thread char b[8]; int n = 0;
        if (live) { n = fmt(b, s.cpu_total * 100.0f, 0, 1); n = cat(b, n, T_PCT); TB(b, n, 150, 954, EM_B, B); }
        seg_bar(a, S, 150, 1001, 20, 30, 21, live ? s.cpu_total : 0.0f, B);
        // per-cluster averages and the GPU beside the big number
        if (live && S.x > 540.0f) {
            const int nc = int(min(s.cpu_count, 32u)), ne = typed_cores(s) ? int(s.cpu_e_cores) : 0;
            float pe = 0.0f, ee = 0.0f;
            for (int i = 0; i < nc; ++i) { if (i < ne) ee += s.cpu_core[i]; else pe += s.cpu_core[i]; }
            for (int r = 0; r < 3; ++r) {
                const float y = 894.0f + 30.0f * float(r);
                if (abs(S.y - y + 8.0f) > 22.0f) continue;
                if (r == 2) { TX(T_GPU, 555, y, EM_N, M); }
                else if (ne == 0) { if (r == 1) continue; TX(T_CPU, 555, y, EM_N, M); }
                else if (r == 0) { TX(T_PCL, 555, y, EM_N, M); } else { TX(T_ECL, 555, y, EM_N, M); }
                const float v = r == 2 ? s.gpu_busy : (ne == 0 ? s.cpu_total : (r == 0 ? pe / float(max(nc - ne, 1)) : ee / float(max(ne, 1))));
                thread char p[8]; int np = fmt(p, v * 100.0f, 0, 1); np = cat(p, np, T_PCT);
                TBR(p, np, 810.0f, y, EM_N, B);
            }
        }
    }
    if (!live) { if (S.x > 850 && S.y > 150 && S.y < 250) TX(H_WAIT, CX0, 234, EM_N, B * blink); return a; }
    const float h = head_g(s, f, m.t_arr);
    const int hi = m.hv, lo = max(int(s.seq) - 255, 1);
    const int hh = min(int(floor(h)) + 1, hi);
    // ---- CPU chart: a ring-buffer sweep, the head writes as the samples arrive
    if (S.x > 820 && S.y > 145 && S.y < 440) {
        TX(T_CPUC, CX0, 174, EM_N, M);
        {   const float4 pa = pv.read(uint2(META_X + 5u, META_Y));   // (peak, average) over the window
            thread char b[40]; int n = cat(b, 0, T_PEAK); n += fmt(b + n, pa.x * 100.0f, 0, 1); n = cat(b, n, T_PCT);
            n = cat(b, n, T_AVG); n += fmt(b + n, pa.y * 100.0f, 0, 1); n = cat(b, n, T_PCT);
            TBR(b, n, CX1, 174, EM_N, M); }
        const float bx = sd_box(S, float2(0.5f * (CX0 + CX1), 0.5f * (CPU_Y0 + CPU_Y1)), float2(0.5f * (CX1 - CX0), 0.5f * (CPU_Y1 - CPU_Y0)), 2.0f);
        put_line(a, abs(bx), 0.8f, Dm);
        if (bx < 0.0f) {
            if (fmod(S.x - CX0, (CX1 - CX0) / 10.0f) < 1.5f && fmod(S.y, 9.0f) < 3.0f) put_fill(a, -1.0f, 0.16f);
            const float gy = CPU_Y0 + 1.5f + 60.0f * round((S.y - CPU_Y0 - 1.5f) / 60.0f);   // grid lines on whole scan lines
            if (abs(S.y - gy) < 0.5f && fmod(S.x, 8.0f) < 3.0f) put_fill(a, -1.0f, 0.16f);
            const float u = (S.x - CX0) / (CX1 - CX0);
            const float age = col_age(u, h, CPU_N);
            const float g = h - age;
            const float dh = head_d(pv, SER_CPU, S, h, CPU_N, CX0, CX1, CPU_Y0 + 2.0f, CPU_Y1 - 2.0f, 1.0f, lo, hi);
            if (age < CPU_N - 2.4f && g >= float(lo)) {
                const float d = trace_d(pv, SER_CPU, S, g, CPU_N, CX0, CX1, CPU_Y0 + 2.0f, CPU_Y1 - 2.0f, 1.0f, lo, hh);
                put_line(a, min(d, dh), 1.2f, 0.72f + 0.5f * exp(-age / 1.5f));
            } else put_line(a, dh, 1.2f, 1.2f);
            TX(T_FS100, CX0 + 15.0f, 234, EM_N, Dm);
        }
    }
    // ---- network chart: RX solid, TX dashed, full scale follows the last minute
    if (S.x > 820 && S.y > 448 && S.y < 650) {
        TX(T_NET, CX0, 474, EM_N, M);
        thread char b[48]; int n = cat(b, 0, T_RX); n = fmt_rate(b, n, s.net_rx_bps); n = cat(b, n, T_TX); n = fmt_rate(b, n, s.net_tx_bps);
        TBR(b, n, CX1, 474, EM_N, B);
        const float bx = sd_box(S, float2(0.5f * (CX0 + CX1), 0.5f * (NET_Y0 + NET_Y1)), float2(0.5f * (CX1 - CX0), 0.5f * (NET_Y1 - NET_Y0)), 2.0f);
        put_line(a, abs(bx), 0.8f, Dm);
        {   thread char c[32]; int nc = cat(c, 0, T_FS); nc = fmt_rate(c, nc, m.scale_net * 1e6f); TB(c, nc, CX0 + 15.0f, 534, EM_N, Dm); }
        if (bx < 0.0f) {
            const float u = (S.x - CX0) / (CX1 - CX0);
            const float age = col_age(u, h, NET_N);
            const float g = h - age;
            if (age >= NET_N - 1.2f) put_line(a, head_d(pv, SER_RX, S, h, NET_N, CX0, CX1, NET_Y0 + 2.0f, NET_Y1 - 2.0f, m.scale_net, lo, hi), 1.2f, 1.2f);
            if (age < NET_N - 1.2f && g >= float(lo)) {
                const float fr = exp(-age / 1.5f);
                put_line(a, trace_d(pv, SER_RX, S, g, NET_N, CX0, CX1, NET_Y0 + 2.0f, NET_Y1 - 2.0f, m.scale_net, lo, hh), 1.2f, 0.7f + 0.5f * fr);
                {   // TX dashed: only the beam is blanked between dashes, so its glow stays continuous
                    const float dt = trace_d(pv, SER_TX, S, g, NET_N, CX0, CX1, NET_Y0 + 2.0f, NET_Y1 - 2.0f, m.scale_net, lo, hh);
                    const float bt = 0.45f + 0.3f * fr;
                    a.x = max(a.x, bt * saturate(1.5f - dt) * (fmod(S.x, 10.0f) < 6.0f ? 1.0f : 0.0f));
                    a.y = max(a.y, 0.6f * bt * exp(-max(dt - 1.0f, 0.0f) / 6.0f));
                }
            }
        }
    }
    // ---- memory
    if (S.x > 820 && S.y > 655 && S.y < 790) {
        TX(T_MEM, CX0, 684, EM_N, M);
        thread char b[24]; int n = fmt(b, s.mem_used_gb, 1, 1); n = cat(b, n, T_OF); n += fmt(b + n, s.mem_total_gb, 1, 1); n = cat(b, n, T_GB);
        TB(b, n, CX0 + 150.0f, 684, EM_N, B);
        const int nw = slen(press_word(s.mem_pressure));
        TXR(T_PR, CX1 - tw(nw, EM_N), 684, EM_N, M);
        if (s.mem_pressure == 0) TXR(press_word(0), CX1, 684, EM_N, M)
        else { const float2 o = float2(CX1 - tw(nw, EM_N), 684); put_rev(a, text_sd(pv, S, o, EM_N, press_word(s.mem_pressure), nw, 0), S, o, nw, EM_N, B * (s.mem_pressure > 1 ? blink : 1.0f)); }
        if (S.y > 702 && S.y < 732 && S.x > CX0 && S.x < CX1) {
            const int cells = 40; const float cw = (CX1 - CX0) / float(cells);
            const float cx = (S.x - CX0) / cw; const int ci = int(cx); const float fx = cx - float(ci);
            const float gq = (float(ci) + 0.5f) / float(cells) * max(s.mem_total_gb, 1.0f);
            const float app = max(s.mem_used_gb - s.mem_wired_gb - s.mem_compressed_gb, 0.0f);
            if (fx > 0.12f && fx < 0.88f) {
                if (gq < s.mem_wired_gb) put_fill(a, -1.0f, 0.95f);
                else if (gq < s.mem_wired_gb + app) put_fill(a, -1.0f, 0.6f);
                else if (gq < s.mem_used_gb) { if (fmod(floor(S.y / PITCH), 2.0f) < 1.0f) put_fill(a, -1.0f, 0.6f); }
                else put_line(a, min(min(fx - 0.12f, 0.88f - fx) * cw, min(S.y - 702.0f, 732.0f - S.y)), 0.7f, 0.3f);
            }
        }
        if (S.y > 750.0f && S.y < 785.0f) {
            constant char* lw[4] = {T_LW, T_LA, T_LC, T_LF};
            float x = CX0;
            for (int i = 0; i < 4; ++i) {   // a swatch in one cell, then the word
                const float sw = sd_box(S, float2(x + 7.5f, 763.5f), float2(5.0f, 7.5f), 0.0f);
                if (i == 0) put_fill(a, sw, 0.95f); else if (i == 1) put_fill(a, sw, 0.6f);
                else if (i == 2) { if (fmod(floor(S.y / PITCH), 2.0f) < 1.0f) put_fill(a, sw, 0.6f); } else put_line(a, abs(sw), 0.7f, 0.3f);
                const int n = slen(lw[i]); TB(lw[i], n, x + 30.0f, 774.0f, EM_N, Dm); x += tw(n + 4, EM_N);
            }
            thread char l[24]; int nl = cat(l, 0, T_SWAP); nl += fmt(l + nl, s.swap_used_gb, 2, 1); nl = cat(l, nl, T_GB);
            TBR(l, nl, CX1, 774, EM_N, Dm);
        }
    }
    // ---- processes (the user's own, highest CPU first); % CPU as Activity Monitor counts it (one core = 100)
    if (S.x > 820 && S.y > 800 && S.y < 1010) {
        TX(T_PROC, CX0, 834, EM_N, M); TXR(T_PCPU, 1335, 834, EM_N, M); TXR(T_PMEM, 1515, 834, EM_N, M);
        for (int i = 0; i < int(min(s.proc_count, 5u)); ++i) {
            const float y = 864.0f + 30.0f * float(i);
            if (abs(S.y - y + 8.0f) > 22.0f) continue;
            constant uchar* nm = s.procs[i].name;
            TB(nm, min(pname_len(nm), 18), CX0, y, EM_N, B * 0.9f);
            const float pc = s.procs[i].cpu * float(s.cpu_count) * 100.0f;
            thread char p[12]; const int np = fmt(p, pc, 1, 1); TBR(p, np, 1335, y, EM_N, B * 0.9f);
            thread char q[12]; const int nq = fmt(q, s.procs[i].mem_gb, 2, 1); TBR(q, nq, 1515, y, EM_N, M);
            seg_bar(a, S, 1545, y, 16, 15, 15, s.procs[i].cpu * 4.0f, 0.8f);   // full bar = a quarter of the machine
        }
    }
    // ---- footer: power, disk, thermal, uptime
    if (S.x > 120 && S.x < 1800) put_line(a, abs(S.y - 1035.0f), 0.8f, Dm);
    if (S.y > 1043 && S.y < 1082) {
        thread char b[48]; int n = 0;
        if (s.battery_present == 0) n = cat(b, 0, T_AC);
        else {
            n = cat(b, 0, T_BATT); n += fmt(b + n, s.battery_charge * 100.0f, 0, 1); n = cat(b, n, T_PCT);
            if (s.battery_charging != 0) n = cat(b, n, T_CHG);
            if (s.battery_minutes < 0.0f) n = cat(b, n, T_CALC);
            else if (s.battery_minutes > 0.0f) {
                const int mins = int(s.battery_minutes); b[n++] = ' '; n += fmt(b + n, float(mins / 60), 0, 1); b[n++] = ':'; n = cat2(b, n, mins % 60);
                n = cat(b, n, s.battery_charging != 0 ? T_TOFULL : T_LEFT);
            } else if (s.on_ac != 0) { b[n++] = ' '; b[n++] = 'A'; b[n++] = 'C'; }
        }
        const bool low = s.battery_present != 0 && s.on_ac == 0 && s.battery_charge < 0.2f;
        if (low) put_rev(a, text_sd(pv, S, float2(150, 1074), EM_N, b, n, 0), S, float2(150, 1074), n, EM_N, B * blink);
        else TB(b, n, 150, 1074, EM_N, M);
        thread char d[32]; int nd = cat(d, 0, T_DISK); nd += fmt(d + nd, s.disk_free_gb, 0, 1); nd = cat(d, nd, T_FREE);
        TB(d, nd, 690, 1074, EM_N, M);
        TX(T_TH, 1065, 1074, EM_N, M);
        const int nt = slen(therm_word(s.thermal)); const float2 to = float2(1065.0f + tw(8, EM_N), 1074.0f);
        if (s.thermal == 0) put_text(a, text_sd(pv, S, to, EM_N, therm_word(0), nt, 0), EM_N, M);
        else put_rev(a, text_sd(pv, S, to, EM_N, therm_word(s.thermal), nt, 0), S, to, nt, EM_N, B * (s.thermal > 1 ? blink : 1.0f));
        thread char u[24]; int nu = cat(u, 0, T_UP); const uint up = s.uptime_s;
        nu += fmt(u + nu, float(up / 86400u), 0, 1); nu = cat(u, nu, T_D); nu = cat2(u, nu, int((up / 3600u) % 24u)); u[nu++] = ':'; nu = cat2(u, nu, int((up / 60u) % 60u));
        TBR(u, nu, 1785, 1074, EM_N, M);
    }
    // ---- the log line, typed at 300 baud (30 characters a second), and the cursor
    if (S.y > 1080 && S.y < 1120 && S.x < 1800) {
        const int len = int(pv.read(uint2(META_X, MSG_Y)).y);
        const float t0 = floor(f.time / 10.0f) * 10.0f;
        const int vis = min(len, int((f.time - t0) * 30.0f));
        thread char l[64]; for (int i = 0; i < vis; ++i) l[i] = char(int(pv.read(uint2(META_X + uint(i), MSG_Y)).x));
        TB(l, vis, 150, 1104, EM_N, M);
        const float cx = 150.0f + tw(vis, EM_N) + 0.5f * ADV * EM_N;
        // the IBM PC's default cursor: an underline two scan lines tall, blinking once output stops
        if (vis < len || fract(f.time) < 0.5f) put_fill(a, sd_box(S, float2(cx, 1107.0f), float2(0.5f * ADV * EM_N - 1.0f, 3.0f), 0.0f), B);
    }
    return a;
}

// the log message for message slot mi (one every 10 s), composed once from the live sample
constant char L_SAMPLE[] = "> SAMPLE "; constant char L_RECV[] = " RECEIVED. "; constant char L_OK[] = "ALL SYSTEMS NOMINAL.";
constant char L_PW[] = "MEMORY PRESSURE "; constant char L_THW[] = "THERMAL STATE "; constant char L_DOT[] = ".";
constant char L_TOP[] = "> TOP PROCESS: "; constant char L_CPUP[] = "% CPU, "; constant char L_GBM[] = " GB.";
constant char L_NET[] = "> NETWORK: RX "; constant char L_TX[] = ", TX ";
constant char L_PWR[] = "> POWER: "; constant char L_DISK[] = "> DISK: "; constant char L_OFT[] = " GB FREE OF ";
constant char L_UPT[] = " GB. UP "; constant char L_DAYS[] = " DAYS.";
static int compose_msg(thread char* b, uint mi, constant ArgusStats& s) {
    int n = 0;
    switch (mi % 5u) {
    case 0: {
        n = cat(b, 0, L_SAMPLE); n += fmt(b + n, float(s.seq), 0, 6); n = cat(b, n, L_RECV);
        if (s.mem_pressure > 0) { n = cat(b, n, L_PW); n = cat(b, n, press_word(s.mem_pressure)); n = cat(b, n, L_DOT); }
        else if (s.thermal > 0) { n = cat(b, n, L_THW); n = cat(b, n, therm_word(s.thermal)); n = cat(b, n, L_DOT); }
        else n = cat(b, n, L_OK);
        break; }
    case 1:
        if (s.proc_count > 0) {
            n = cat(b, 0, L_TOP); const int k = min(pname_len(s.procs[0].name), 24);
            for (int i = 0; i < k; ++i) b[n++] = char(s.procs[0].name[i]);
            b[n++] = ','; b[n++] = ' '; n += fmt(b + n, s.procs[0].cpu * float(s.cpu_count) * 100.0f, 1, 1); n = cat(b, n, L_CPUP);
            n += fmt(b + n, s.procs[0].mem_gb, 2, 1); n = cat(b, n, L_GBM);
            break;
        } // fall through
    case 2: n = cat(b, 0, L_NET); n = fmt_rate(b, n, s.net_rx_bps); n = cat(b, n, L_TX); n = fmt_rate(b, n, s.net_tx_bps); n = cat(b, n, L_DOT); break;
    case 3: {
        n = cat(b, 0, L_PWR);
        if (s.battery_present == 0) n = cat(b, n, T_AC);
        else {
            n = cat(b, n, T_BATT); n += fmt(b + n, s.battery_charge * 100.0f, 0, 1); n = cat(b, n, T_PCT);
            if (s.battery_charging != 0) n = cat(b, n, T_CHG); else if (s.on_ac != 0) { b[n++] = ','; b[n++] = ' '; n = cat(b, n, T_AC); }
        }
        n = cat(b, n, L_DOT); break; }
    default: {
        n = cat(b, 0, L_DISK); n += fmt(b + n, s.disk_free_gb, 0, 1); n = cat(b, n, L_OFT); n += fmt(b + n, s.disk_total_gb, 0, 1);
        n = cat(b, n, L_UPT); n += fmt(b + n, float(s.uptime_s) / 86400.0f, 1, 1); n = cat(b, n, L_DAYS); break; }
    }
    return min(n, 63);
}

// ---------------------------------------------------------------------------------- kernels
kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       texture2d<float, access::read> data [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    float4 v = float4(0.0f);
    if (gid.y >= ATLAS_Y && gid.x < 1024u) v = data.read(uint2(gid.x, gid.y - ATLAS_Y));
    if (gid.y == META_Y && gid.x == META_X) v = float4(4095.0f, 0.0f, 0.0f, 255.0f);
    if (gid.y == META_Y && gid.x == META_X + 3u) v = float4(0.1f, 0.0f, 0.0f, 0.0f);
    if (gid.y == META_Y && gid.x == META_X + 4u) v = float4(-1.0f, 0.0f, 0.0f, 0.0f);
    state.write(v, gid);
}

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> pv [[texture(0)]],
                       texture2d<float, access::write> nx [[texture(1)]],
                       constant ArgusStats& s [[buffer(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const float4 m0 = pv.read(uint2(META_X, META_Y));
    const uint SEQM = 4194304u;   // seq kept as lo + 2048 hi (both exact in half floats), mod 2^22
    const uint prev = uint(m0.z) * 2048u + uint(m0.x);
    const bool none = m0.x > 4000.0f;
    const bool fresh = s.seq > 0 && (none || (s.seq % SEQM) != prev);
    const uint delta = fresh && !none ? (s.seq + SEQM - prev) % SEQM : 1u;   // 1 unless samples were skipped
    const float rt = fresh ? 0.0f : min(m0.w + 1.0f, 255.0f);   // ticks since the newest sample arrived
    Meta m;
    m.t_arr = fresh ? f.time : join_time(pv.read(uint2(META_X + 1u, META_Y)));
    m.scale_net = max(pv.read(uint2(META_X + 3u, META_Y)).x, 0.1f);
    m.hv = fresh ? int(s.seq) - 1 : int(s.seq);
    float4 o = pv.read(gid);
    if (gid.y < uint(LINES)) {
        // ---- a scan line: repaint (whole screen top to bottom over 4 ticks after a sample; animated
        // regions every tick), then the phosphor: what the beam writes now and the decaying ghost
        if (gid.x >= uint(VW)) { nx.write(float4(0.0f), gid); return; }
        const float2 S = float2(float(gid.x) + 0.5f, (float(gid.y) + 0.5f) * PITCH);
        // the repaint bands end in gaps of the layout, so no reading is torn between two ticks
        const uint band = gid.y < 150u ? 0u : gid.y < 215u ? 1u : gid.y < 278u ? 2u : 3u;
        bool redo = f.frame < 3u || (rt < 4.0f && band == uint(rt)) || (s.seq == 0 && S.y > 150.0f && S.y < 250.0f && S.x > 820.0f);
        if (!redo && s.seq > 0) {
            if (S.y > 1080.0f && S.y < 1120.0f) redo = true;                         // log line + cursor
            else if (S.y > 80.0f && S.y < 120.0f && S.x > 1100.0f) redo = true;      // clock
            else if (S.x > CX0 - 2.0f && S.x < CX1 + 2.0f && ((S.y > CPU_Y0 - 2.0f && S.y < CPU_Y1 + 2.0f) || (S.y > NET_Y0 - 2.0f && S.y < NET_Y1 + 2.0f))) {
                const float u = (S.x - CX0) / (CX1 - CX0);
                const float N = S.y < 450.0f ? CPU_N : NET_N;
                const float age = col_age(u, head_g(s, f, m.t_arr), N);
                redo = age < 3.0f || age > N - 3.0f;                                   // around the head and its gap
            } else if ((S.y > 650.0f && S.y < 700.0f && S.x > 1500.0f) || (S.y > 1043.0f && S.y < 1082.0f && S.x < 1500.0f)) redo = true;  // blinking words
        }
        const float2 c = redo ? content(pv, f, s, m, S) : o.xy;
        const float k1 = exp(-f.dt / TAU_FAST), k2 = exp(-f.dt / TAU_TAIL);
        // o.z: fast ghost, o.w: slow tail (both of the sharp channel)
        const float g1 = max((1.0f - TAIL) * c.x, o.z * k1), g2 = max(TAIL * c.x, o.w * k2);
        nx.write(float4(c, g1, g2), gid);
        return;
    }
    if (gid.y >= ATLAS_Y && gid.x < 1024u) { if (f.frame < 3u) nx.write(o, gid); return; }
    if (gid.y >= HIST_Y && gid.y < HIST_Y + 4u && gid.x >= HIST_X && gid.x < HIST_X + 256u) {
        const uint j = gid.x - HIST_X;
        if (fresh && j == (s.seq & 255u)) {   // rates in MB/s; .y = 1: a recorded sample
            const uint sr = gid.y - HIST_Y;
            o.x = sr == SER_CPU ? s.cpu_total : sr == SER_GPU ? s.gpu_busy : min((sr == SER_RX ? s.net_rx_bps : s.net_tx_bps) * 1e-6f, 6.0e4f);
            o.y = 1.0f;
        } else if (fresh && delta > 1u && ((j + 256u - ((prev + 1u) & 255u)) & 255u) < min(delta - 1u, 256u)) o.y = 0.0f;   // skipped
        nx.write(o, gid);
        return;
    }
    if (gid.y == META_Y && gid.x >= META_X && gid.x < META_X + 48u) {
        const uint k = gid.x - META_X;
        if (k == 0u) o = fresh ? float4(float(s.seq % 2048u), 0.0f, float((s.seq / 2048u) % 2048u), rt) : float4(m0.xyz, rt);
        else if (k == 1u) o = fresh ? split_time(f.time) : o;
        else if (k == 2u) o = split_time(f.time);
        else if (k == 3u) {
            if (fresh || f.frame < 3u) {   // full scale: the last minute's peak (and this sample), on a 1-2-5 ladder
                float pk = max(s.net_rx_bps, s.net_tx_bps) * 1e-6f;
                for (int i = 1; i < 60; ++i) { const int g = int(s.seq) - i; if (g < 1) break;
                    if (histv(pv, SER_CPU, g).y < 0.5f) continue;
                    pk = max(pk, max(hist(pv, SER_RX, g), hist(pv, SER_TX, g))); }
                float sc = 0.1f;   // MB/s, 0.1 at least
                for (int i = 0; i < 30 && sc < pk * 1.05f; ++i) { const float d = floor(log10(sc) + 1e-4f); const float mant = sc / pow(10.0f, d); sc = (mant < 1.5f ? 2.0f : mant < 3.5f ? 5.0f : 10.0f) * pow(10.0f, d); }
                o.x = sc;
            }
        } else if (k == 4u) o.x = floor(f.time / 10.0f);
        else if (k == 5u) {
            if (fresh || f.frame < 3u) {
                float pk = s.cpu_total, sum = s.cpu_total; int cnt = 1;
                for (int i = 1; i < int(CPU_N); ++i) { const int g = int(s.seq) - i; if (g < 1) break;
                    const float2 v = histv(pv, SER_CPU, g); if (v.y < 0.5f) continue; pk = max(pk, v.x); sum += v.x; ++cnt; }
                o.x = pk; o.y = sum / float(cnt);
            }
        }
        else if (k >= 8u && k < 8u + 33u) {
            // damped block level (x, v): critically damped toward the live value
            const int i = int(k - 8u); const int n = int(min(s.cpu_count, 32u));
            const float T = i < n ? s.cpu_core[i] : (i == 32 ? s.gpu_busy : 0.0f);
            if (f.frame < 2u) o = float4(T, 0.0f, 0.0f, 0.0f);
            else {
                const float e = o.x - T, v = o.y, dt = f.dt, ex = exp(-OMEGA * dt);
                o.x = T + (e + (v + OMEGA * e) * dt) * ex;
                o.y = (v - OMEGA * (v + OMEGA * e) * dt) * ex;
            }
        }
        nx.write(o, gid);
        return;
    }
    if (gid.y == MSG_Y && gid.x >= META_X && gid.x < META_X + 64u) {
        const uint mi = uint(floor(f.time / 10.0f));
        const float last = pv.read(uint2(META_X + 4u, META_Y)).x;
        if (f.frame < 3u || float(mi) != last) {
            thread char b[64]; const int n = s.seq > 0 ? compose_msg(b, mi, s) : 0;
            const int i = int(gid.x - META_X);
            o = float4(i < n ? float(int(b[i])) : 32.0f, float(n), 0.0f, 0.0f);
        }
        nx.write(o, gid);
        return;
    }
    nx.write(o, gid);
}

// ---------------------------------------------------------------------------------- draw: beam, glass, bezel
static float3 hammertone(float2 P, float3 base) {
    const float n = argus_noise(P * 0.07f) + 0.6f * argus_noise(P * 0.17f + 3.0f) + 0.3f * argus_noise(P * 0.5f);
    return base * (1.0f + 0.07f * n) + 0.012f * pow(saturate(n * 0.5f + 0.2f), 4.0f);
}
// live block fills (drawn per frame so the damped levels move smoothly at any frame rate)
static float block_fill(float2 S, constant ArgusStats& s, texture2d<float> st, float tau) {
    if (s.seq == 0 || S.x < 160.0f || S.x > 720.0f || S.y < 190.0f || S.y > 600.0f) return 0.0f;
    const int nb = int(min(s.cpu_count, 32u)) + 1;
    for (int i = 0; i < nb; ++i) {
        const Blk k = block(i, s);
        const float bd = sd_box(S, k.c, k.h, 3.0f);
        if (bd > -2.0f) continue;
        const float4 xv = st.read(uint2(META_X + 8u + uint(i < nb - 1 ? i : 32), META_Y));
        const float T = i < nb - 1 ? s.cpu_core[i] : s.gpu_busy;
        const float e = xv.x - T;
        const float x = saturate(T + (e + (xv.y + OMEGA * e) * tau) * exp(-OMEGA * tau));
        const float lby = gbase_at_or_below(k.c.y - k.h.y + 21.0f);   // the label row stays clear: the fill's scale is the box below it
        const float lb = lby > k.c.y + k.h.y - 2.0f ? 0.0f : lby + 5.0f - (k.c.y - k.h.y);
        const float lvl = k.c.y + k.h.y - (2.0f * k.h.y - lb) * x;
        const float line = saturate(1.7f - abs(S.y - lvl));
        return max(line, (S.y > lvl && bd < -4.0f) ? 0.28f + 0.25f * x : 0.0f);
    }
    return 0.0f;
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> st [[texture(1)]],
                       constant ArgusStats& s [[buffer(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float sc = min(float(f.height) / VH, float(f.width) / VW);   // the face fits any screen shape
    const float2 P = (float2(gid) + 0.5f - 0.5f * float2(f.width, f.height)) / sc + 0.5f * float2(VW, VH);
    const float2 q = (P - FACE_C) / FACE_H;
    const float2 S = FACE_C + q * (1.0f + FACE_K * dot(q, q)) * FACE_H;
    const float edge = sd_box(S, FACE_C, FACE_H, FACE_R);
    float3 col = float3(0.0f);
    if (edge < 0.5f) {
        constexpr sampler ls(filter::linear, address::clamp_to_edge);
        const float tau = wrap_dt(f.time - join_time(st.read(uint2(META_X + 2u, META_Y))));
        const float kf = floor(S.y / PITCH - 0.5f);
        float I = 0.0f, G = 0.0f;
        for (int j = 0; j < 2; ++j) {
            const float line = kf + float(j);
            if (line < 0.0f || line >= float(LINES)) continue;
            const float yk = (line + 0.5f) * PITCH;
            const float4 t = st.sample(ls, float2(S.x / float(f.state_width), (line + 0.5f) / float(f.state_height)));
            float sharp = max(t.x, t.z + t.w);
            sharp = max(sharp, block_fill(float2(S.x, yk), s, st, tau));
            const float sig = PITCH * (0.24f + 0.20f * saturate(sharp));   // the spot grows with beam current
            I += sharp * exp(-0.5f * sq((S.y - yk) / sig)) * 1.25f;
            G += max(t.y, 0.5f * (t.z + t.w)) * (1.0f - abs(S.y - yk) / PITCH);
        }
        const float E = I + 0.16f * G;
        // P39 / willemite x 0.21, y 0.71 lies outside sRGB; clipped per channel it is (0, 1, 0), the green a
        // monitor shows; a small floor of red and blue keeps faint strokes from going neon (CHOSEN)
        const float3 ph = float3(0.04f, 1.0f, 0.07f);
        col = float3(0.010f, 0.013f, 0.011f) * (1.0f - 0.4f * dot(q, q));
        col += ph * E * 0.85f + float3(0.75f, 1.0f, 0.8f) * max(E - 0.85f, 0.0f) * 0.5f;
        const float band = fmod(f.time * 42.5f, 1700.0f) - 250.0f;   // CHOSEN: a faint rolling band (a film artefact)
        col *= 1.0f + 0.05f * exp(-sq((S.y - band) / 55.0f));
        col *= (1.0f - 0.5f * pow(saturate(length(q) * 0.78f), 4.0f)) * (1.0f - 0.18f * sq(saturate(abs(q.x) * abs(q.y) * 1.1f)));
        const float2 rq = (q - float2(-0.50f, -0.60f)) / float2(0.45f, 0.22f);
        col += float3(0.026f, 0.029f, 0.032f) * exp(-dot(rq, rq));
        col += float3(0.05f) * exp(-sq((edge + 3.0f) / 3.0f)) * saturate(-q.y * 0.8f + 0.3f);
    }
    if (edge > -0.5f) {
        // painted steel with a fine orange-peel grain, lit from above; a 9 px chamfer down to the glass
        float3 b = float3(0.021f, 0.023f, 0.021f) * (1.0f + 0.025f * argus_noise(P * 0.35f) + 0.015f * argus_noise(P * 1.3f));
        b *= 1.05f - 0.25f * P.y / VH;
        const float2 nq = normalize(q + 1e-4f);
        const float lit = -nq.y;   // the lip facing up is lit, the one facing down in shadow
        const float ch = saturate(1.0f - edge / 9.0f);
        b *= 1.0f + ch * (lit > 0.0f ? 0.12f : 0.20f) * lit * 2.0f - 0.55f * exp(-max(edge, 0.0f) / 3.0f);
        b += float3(0.035f) * exp(-sq((edge - 9.0f) / 1.2f)) * saturate(lit + 0.3f);
        col = over(col, b, saturate(edge + 0.5f));
    }
    col = 1.0f - exp(-col * 1.1f);
    out.write(float4(argus_srgb(col), 1.0f), gid);
}
