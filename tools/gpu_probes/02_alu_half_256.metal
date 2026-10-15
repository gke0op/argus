kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    half a = half(uv.x + f.time), b = half(uv.y);
    for (int i = 0; i < 256; i++) { a = fma(a, 0.999h, b); b = fma(b, 1.0001h, -a * 0.001h); }
    float r = fract(float(a + b));
    out.write(float4(saturate(float3(r, fract(r * 3.1f), uv.x)), 1.0f), gid);
}
