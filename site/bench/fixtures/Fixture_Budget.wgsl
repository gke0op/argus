// Fixture_Budget.wgsl: fails the GPU frame budget (8,333 us). Correct and animated, but every
// pixel iterates a 3,000-step loop of transcendentals: far too much work for one frame.
const ITER: i32 = 3000;
@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let uv = argus_uv(gid, f);
    var z = uv;
    var acc = 0.0;
    for (var i = 0; i < ITER; i++) {
        z = vec2f(sin(z.y * 1.7 + f.time), cos(z.x * 1.3 - f.time * 0.7)) * 0.98 + uv * 0.02;
        acc += exp(-8.0 * dot(z, z));
    }
    let c = argus_palette(acc / f32(ITER) * 4.0, vec3f(0.5), vec3f(0.5), vec3f(1.0), vec3f(0.1, 0.4, 0.7));
    textureStore(argus_out, gid, vec4f(c, 1.0));
}
