kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    float r = fract(f.time + uv.y);
    out.write(float4(saturate(float3(r, fract(r * 3.1f), uv.x)), 1.0f), gid);
}
