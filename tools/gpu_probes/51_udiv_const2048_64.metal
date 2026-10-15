kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    uint a = gid.x * 7919u + gid.y * 104729u + f.frame, acc = 0u;
    for (int i = 0; i < 64; i++) { a = a * 1664525u + 1013904223u; acc += a / 2048u + a % 2048u; }
    out.write(float4(float(acc & 255u) / 255.0f, 0.2f, 0.3f, 1.0f), gid);
}
