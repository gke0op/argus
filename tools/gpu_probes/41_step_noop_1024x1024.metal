// @argus state 1024x1024
kernel void argus_step(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::read> prev [[texture(0)]], texture2d<float, access::write> next [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.y > 4u) return; next.write(prev.read(gid), gid);
}
kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], texture2d<float> st [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    out.write(float4(fract(f.time + float(gid.x) * 0.001f), 0.2f, 0.3f, 1.0f), gid);
}
