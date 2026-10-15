const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast,
    });

    // 1. argus-desktop: bare-metal macOS multi-Space live wallpaper engine
    const desktop_exe = b.addExecutable(.{
        .name = "argus-desktop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/desktop_wallpaper.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(desktop_exe);

    // 2. kronos-tui: Standalone Symplectic Yoshida-4 Magneto-Vortex + SIMD Wave Lattice TUI
    const kronos_exe = b.addExecutable(.{
        .name = "kronos-tui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kronos_tui.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(kronos_exe);

    // Run steps
    const run_desktop = b.addRunArtifact(desktop_exe);
    run_desktop.step.dependOn(b.getInstallStep());
    run_desktop.addPassthruArgs();
    b.step("run", "Run the macOS live desktop wallpaper engine").dependOn(&run_desktop.step);

    const run_kronos = b.addRunArtifact(kronos_exe);
    run_kronos.step.dependOn(b.getInstallStep());
    run_kronos.addPassthruArgs();
    b.step("run-kronos", "Run the standalone KRONOS-17 symplectic wave TUI").dependOn(&run_kronos.step);

    // Unified test suite
    const test_step = b.step("test", "Run the engine and kronos-tui test suites");

    const test_files = [_][]const u8{
        "src/desktop_wallpaper.zig",
        "src/kronos_tui.zig",
    };
    for (test_files) |tf| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(tf),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }
}
