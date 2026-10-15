kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    float a = uv.x + f.time, b = uv.y;
    const int n = int(255.0f * (0.5f + 0.5f * sin(float(gid.x) * 0.01f)));
    for (int i = 0; i < n; i++) { a = fma(a, 0.999f, b); b = fma(b, 1.0001f, -a * 0.001f); }
    float r = fract(a + b);
    out.write(float4(saturate(float3(r, fract(r * 3.1f), uv.x)), 1.0f), gid);
}
