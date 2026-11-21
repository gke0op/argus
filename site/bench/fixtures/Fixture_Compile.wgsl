// Fixture_Compile.wgsl: fails Gate 1. WGSL has no implicit conversions: f32 * u32 does not compile.
// (The same trap as Metal → WGSL translation rule 1 in web/README.md.)
@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let shade = f.time * gid.x;   // error: f32 * u32
    textureStore(argus_out, gid, vec4f(shade, 0.0, 0.0, 1.0));
}
