// Fixture_NaN.wgsl: fails the NaN / Inf check. A moving gradient, with a NaN written into one
// pixel in every 64. The NaN is built at run time (a NaN constant is a WGSL compile error).
@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let uv = argus_uv01(gid, f.width, f.height);
    var c = 0.5 + 0.5 * cos(f.time + uv.xyx * 3.0 + vec3f(0.0, 2.0, 4.0));
    if ((gid.x & 7u) == 0u && (gid.y & 7u) == 0u) { c.r = bitcast<f32>(0x7fc00000u | (f.seed & 0u)); }
    textureStore(argus_out, gid, vec4f(c, 1.0));
}
