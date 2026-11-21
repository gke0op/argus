// Fixture_Frozen.wgsl: fails Temporal Motion. A rich still image: nothing reads f.time, so
// frame 120 equals frame 1 and no pixel is animated.
@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let uv = argus_uv(gid, f);
    let c = argus_palette(argus_fbm(uv * 3.0, 5), vec3f(0.5), vec3f(0.5), vec3f(1.0), vec3f(0.0, 0.33, 0.67));
    textureStore(argus_out, gid, vec4f(c, 1.0));
}
