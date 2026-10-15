// @argus state 1024x1024
kernel void argus_init(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> state [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    state.write(float4(argus_rand(gid, 1u), argus_rand(gid, 2u), 0.0f, 1.0f), gid);
}
kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], texture2d<float> st [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    constexpr sampler sm(filter::linear, address::repeat);
    float r = 0.0f;
    uint s = gid.x * 2654435761u ^ gid.y * 40503u ^ f.frame;
    for (int i = 0; i < 32; i++) { s = s * 1664525u + 1013904223u; r += st.sample(sm, float2(s >> 22, (s >> 12) & 1023u) / 1024.0f).x; }
    r = fract(r + f.time);
    out.write(float4(r, fract(r * 3.1f), uv.x, 1.0f), gid);
}
