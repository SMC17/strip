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

    const verification_cli = b.addExecutable(.{
        .name = "strip-verification-gates",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/verification_gates.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(verification_cli);
    const run_verification = b.addRunArtifact(verification_cli);
    run_verification.step.dependOn(&jsbsim_install.step);
    const run_verification_step = b.step("run-verification-gates", "Run JSBSim, OpenVSP, replay, and uncertainty verification gates");
    run_verification_step.dependOn(&run_verification.step);

    const evidence_cli = b.addExecutable(.{
        .name = "strip-evidence",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/strip_evidence.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(evidence_cli);
    const run_evidence = b.addRunArtifact(evidence_cli);
    run_evidence.addArg("build");
    run_evidence.addArg("programs/reference-uas.toml");
    const run_evidence_step = b.step("run-evidence-build", "Compile reference program evidence bundle");
    run_evidence_step.dependOn(&run_evidence.step);

    const campaign_cli = b.addExecutable(.{
        .name = "strip-campaign",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/campaign_run.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(campaign_cli);
    const run_campaign = b.addRunArtifact(campaign_cli);
    run_campaign.addArg("run");
    run_campaign.addArg("campaigns/reference-uas-contingency.toml");
    const run_campaign_step = b.step("run-campaign", "Run reference UAS contingency campaign scaffold");
    run_campaign_step.dependOn(&run_campaign.step);

    const mesh_digest_cli = b.addExecutable(.{
        .name = "strip-mesh-digest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/mesh_digest.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(mesh_digest_cli);

    const verify_cli = b.addExecutable(.{
        .name = "strip-verify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/strip_verify.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(verify_cli);
    const run_verify_cli = b.addRunArtifact(verify_cli);
    const run_verify_step = b.step("run-strip-verify", "Run Strip Verify credibility checks");
    run_verify_step.dependOn(&run_verify_cli.step);

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

    const hil_bench_cli = b.addExecutable(.{
        .name = "strip-hil-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/hil_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(hil_bench_cli);
    const run_hil_bench = b.addRunArtifact(hil_bench_cli);
    run_hil_bench.addArg("selftest-unix");

    const flight_seal_cli = b.addExecutable(.{
        .name = "strip-flight-seal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/flight_seal.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(flight_seal_cli);
    const run_flight_seal = b.addRunArtifact(flight_seal_cli);
    run_flight_seal.addArg("build");
    run_flight_seal.addArg("--out");
    run_flight_seal.addArg("flight.evidence");
    run_flight_seal.addArg("--telemetry");
    run_flight_seal.addArg("fixtures/validation/flight-test/heldout-telemetry.csv");
    run_flight_seal.addArg("--require-holdout");

    // Gate flight_test: passed only when verification loads the sealed package.
    run_verification.setEnvironmentVariable("STRIP_FLIGHT_PACKAGE", "flight.evidence");
    run_verification.step.dependOn(&run_flight_seal.step);

    const mavlink_sitl_cli = b.addExecutable(.{
        .name = "strip-mavlink-sitl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/mavlink_sitl.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(mavlink_sitl_cli);
    const run_mavlink_sitl = b.addRunArtifact(mavlink_sitl_cli);
    run_mavlink_sitl.addArg("selftest");

    const trajectory_cli = b.addExecutable(.{
        .name = "strip-trajectory",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/trajectory_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(trajectory_cli);
    const run_trajectory = b.addRunArtifact(trajectory_cli);
    run_trajectory.addArg("selftest");
    const run_trajectory_neg = b.addRunArtifact(trajectory_cli);
    run_trajectory_neg.addArg("audit");
    run_trajectory_neg.addArg("--path");
    run_trajectory_neg.addArg("fixtures/trajectory/unsupported-claim.jsonl");
    run_trajectory_neg.addArg("--expect-fail");

    const certification_delta_cli = b.addExecutable(.{
        .name = "strip-certification-delta",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/certification_delta.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(certification_delta_cli);
    const run_cert_delta = b.addRunArtifact(certification_delta_cli);
    run_cert_delta.addArg("diff");
    run_cert_delta.addArg("programs/reference-uas-models.json");
    run_cert_delta.addArg("programs/reference-uas-models.json");

    const model_passport_cli = b.addExecutable(.{
        .name = "strip-model-passport",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/model_passport.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(model_passport_cli);
    const run_model_passport = b.addRunArtifact(model_passport_cli);
    run_model_passport.addArg("issue");
    run_model_passport.addArg("strip.atmosphere.us76-layered");

    const weathernext_cli = b.addExecutable(.{
        .name = "strip-weathernext",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/weathernext.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(weathernext_cli);
    // Platform-only: install but do not run live fetch from verify.

    const google_cli = b.addExecutable(.{
        .name = "strip-google",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/google.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(google_cli);
    const run_google_catalog = b.addRunArtifact(google_cli);
    run_google_catalog.addArg("catalog");
    const run_google_gemini_fixture = b.addRunArtifact(google_cli);
    run_google_gemini_fixture.addArg("gemini");
    run_google_gemini_fixture.addArg("fixture");

    const dispatch_cli = b.addExecutable(.{
        .name = "strip-dispatch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("apps/dispatch.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "strip", .module = strip_mod }},
        }),
    });
    b.installArtifact(dispatch_cli);
    const run_dispatch = b.addRunArtifact(dispatch_cli);
    run_dispatch.addArg("decide");
    run_dispatch.addArg("--id");
    run_dispatch.addArg("verify-dispatch-smoke");
    run_dispatch.addArg("--part");
    run_dispatch.addArg("135");
    run_dispatch.addArg("--role");
    run_dispatch.addArg("director_of_ops");
    run_dispatch.addArg("--go");
    run_dispatch.addArg("--weather");
    run_dispatch.addArg("platform_candidate");
    run_dispatch.addArg("--weather-marginal");

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
    const gen_fixtures_step = b.step("gen-verification-fixtures", "Emit pinned verification-gate digests for fixtures");
    gen_fixtures_step.dependOn(&run_gen_fixtures.step);

    const verify_step = b.step("verify", "Run tests and integration fixtures");
    verify_step.dependOn(test_step);
    verify_step.dependOn(&run_uas.step);
    verify_step.dependOn(&run_assurance.step);
    verify_step.dependOn(&run_platform.step);
    verify_step.dependOn(&run_validation.step);
    verify_step.dependOn(&run_fidelity.step);
    verify_step.dependOn(&run_verification.step);
    verify_step.dependOn(&run_verify_cli.step);
    verify_step.dependOn(&run_evidence.step);
    verify_step.dependOn(&run_campaign.step);
    verify_step.dependOn(&run_hil_bench.step);
    verify_step.dependOn(&run_flight_seal.step);
    verify_step.dependOn(&run_mavlink_sitl.step);
    verify_step.dependOn(&run_trajectory.step);
    verify_step.dependOn(&run_trajectory_neg.step);
    verify_step.dependOn(&run_cert_delta.step);
    verify_step.dependOn(&run_model_passport.step);
    verify_step.dependOn(&run_dispatch.step);
    verify_step.dependOn(&run_google_catalog.step);
    verify_step.dependOn(&run_google_gemini_fixture.step);
}
