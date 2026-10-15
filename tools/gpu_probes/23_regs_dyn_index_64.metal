kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    float arr[64];
    for (int k = 0; k < 64; k++) arr[k] = uv.x * float(k) + f.time;
    uint s = gid.x * 7u + gid.y;
    float r = 0.0f;
    for (int i = 0; i < 128; i++) { s = s * 1664525u + 1013904223u; r += arr[s >> 26]; }
    r = fract(r);
    out.write(float4(saturate(float3(r, fract(r * 3.1f), uv.x)), 1.0f), gid);
}
