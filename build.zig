const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cli = b.addExecutable(.{
        .name = "bpm2",
        .root_source_file = b.path("zig/src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli.root_module.addImport("storage", b.createModule(.{
        .root_source_file = b.path("zig/src/storage.zig"),
    }));
    cli.root_module.addImport("protocol", b.createModule(.{
        .root_source_file = b.path("zig/src/protocol.zig"),
    }));
    cli.root_module.addImport("render", b.createModule(.{
        .root_source_file = b.path("zig/src/render.zig"),
    }));
    b.installArtifact(cli);

    const daemon = b.addExecutable(.{
        .name = "bpm2d",
        .root_source_file = b.path("zig/src/daemon.zig"),
        .target = target,
        .optimize = optimize,
    });
    daemon.root_module.addImport("storage", b.createModule(.{
        .root_source_file = b.path("zig/src/storage.zig"),
    }));
    daemon.root_module.addImport("protocol", b.createModule(.{
        .root_source_file = b.path("zig/src/protocol.zig"),
    }));
    daemon.root_module.addImport("render", b.createModule(.{
        .root_source_file = b.path("zig/src/render.zig"),
    }));
    b.installArtifact(daemon);

    const run_cli = b.addRunArtifact(cli);
    if (b.args) |args| run_cli.addArgs(args);
    const run_step = b.step("run", "Run bpm2 CLI");
    run_step.dependOn(&run_cli.step);

    const test_step = b.step("test", "Run zig tests");
    const cli_tests = b.addTest(.{
        .root_source_file = b.path("zig/src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_tests.root_module.addImport("storage", b.createModule(.{
        .root_source_file = b.path("zig/src/storage.zig"),
    }));
    cli_tests.root_module.addImport("protocol", b.createModule(.{
        .root_source_file = b.path("zig/src/protocol.zig"),
    }));
    cli_tests.root_module.addImport("render", b.createModule(.{
        .root_source_file = b.path("zig/src/render.zig"),
    }));
    test_step.dependOn(&b.addRunArtifact(cli_tests).step);
}
