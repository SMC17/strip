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

    const uas_cli = b.addExecutable(.{
        .name = "strip-uas-range",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/uas_range.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(uas_cli);

    const run_uas = b.addRunArtifact(uas_cli);
    const run_uas_step = b.step("run-uas", "Run bounded UAS contingency fixtures");
    run_uas_step.dependOn(&run_uas.step);

    const assurance_cli = b.addExecutable(.{
        .name = "strip-assurance",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/assurance_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(assurance_cli);
    const run_assurance = b.addRunArtifact(assurance_cli);
    const run_assurance_step = b.step("run-assurance", "Run requirement-to-evidence fixture");
    run_assurance_step.dependOn(&run_assurance.step);

    const platform_cli = b.addExecutable(.{
        .name = "strip-platform",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/platform_surface.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(platform_cli);
    const run_platform = b.addRunArtifact(platform_cli);
    const run_platform_step = b.step("run-platform", "Inspect product and frontier surface");
    run_platform_step.dependOn(&run_platform.step);

    const validation_cli = b.addExecutable(.{
        .name = "strip-validation",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/validation_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(validation_cli);
    const run_validation = b.addRunArtifact(validation_cli);
    const run_validation_step = b.step("run-validation", "Load source manifests and validation coverage");
    run_validation_step.dependOn(&run_validation.step);

    const fidelity_cli = b.addExecutable(.{
        .name = "strip-fidelity",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/fidelity_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(fidelity_cli);
    const run_fidelity = b.addRunArtifact(fidelity_cli);
    const run_fidelity_step = b.step("run-fidelity", "Run coupled fidelity integration fixture");
    run_fidelity_step.dependOn(&run_fidelity.step);

    const jsbsim_shim = b.addExecutable(.{
        .name = "strip-jsbsim-shim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/jsbsim_shim.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    const jsbsim_install = b.addInstallArtifact(jsbsim_shim, .{});
    b.getInstallStep().dependOn(&jsbsim_install.step);

    const proof_cli = b.addExecutable(.{
        .name = "strip-proof-gates",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/proof_gates.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(proof_cli);
    const run_proof = b.addRunArtifact(proof_cli);
    run_proof.step.dependOn(&jsbsim_install.step);
    const run_proof_step = b.step("run-proof-gates", "Run JSBSim, OpenVSP, replay, and uncertainty proof gates");
    run_proof_step.dependOn(&run_proof.step);

    const replay_baseline_cli = b.addExecutable(.{
        .name = "strip-record-replay-baseline",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/record_replay_baseline.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(replay_baseline_cli);

    const promote_replay_cli = b.addExecutable(.{
        .name = "strip-promote-replay-baseline",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/promote_replay_baseline.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(promote_replay_cli);

    const gen_fixtures = b.addExecutable(.{
        .name = "strip-gen-proof-fixtures",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen_proof_fixtures.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    const run_gen_fixtures = b.addRunArtifact(gen_fixtures);
    const gen_fixtures_step = b.step("gen-proof-fixtures", "Emit pinned proof-gate digests for fixtures");
    gen_fixtures_step.dependOn(&run_gen_fixtures.step);

    const verify_step = b.step("verify", "Run tests and integration fixtures");
    verify_step.dependOn(test_step);
    verify_step.dependOn(&run_uas.step);
    verify_step.dependOn(&run_assurance.step);
    verify_step.dependOn(&run_platform.step);
    verify_step.dependOn(&run_validation.step);
    verify_step.dependOn(&run_fidelity.step);
    verify_step.dependOn(&run_proof.step);
}
