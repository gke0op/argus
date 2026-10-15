kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    float a = uv.x + f.time;
    for (int i = 0; i < 64; i++) { a = fast::sin(a * 1.7f + 0.3f); }
    float r = fract(a);
    out.write(float4(saturate(float3(r, fract(r * 3.1f), uv.x)), 1.0f), gid);
}
