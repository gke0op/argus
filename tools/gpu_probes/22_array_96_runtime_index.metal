kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    float acc[96];
    for (int k = 0; k < 96; k++) acc[k] = uv.x * float(k) + f.time;
    for (int i = 0; i < 64; i++) { for (int k = 0; k < 96; k++) acc[k] = fma(acc[k], 0.999f, acc[(k + 1) % 96] * 0.001f); }
    float r = 0.0f; for (int k = 0; k < 96; k++) r += acc[k];
    r = fract(r);
    out.write(float4(saturate(float3(r, fract(r * 3.1f), uv.x)), 1.0f), gid);
}
