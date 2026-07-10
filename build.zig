const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const strip_mod = b.addModule("strip", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = strip_mod });
    const test_step = b.step("test", "Run Strip unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const cli = b.addExecutable(.{
        .name = "strip",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(cli);

    const run_cli = b.addRunArtifact(cli);
    if (b.args) |args| run_cli.addArgs(args);
    const run_step = b.step("run", "Run an evidence-bearing atmosphere query");
    run_step.dependOn(&run_cli.step);
}
