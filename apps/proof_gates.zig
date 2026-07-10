//! Execute the four proof gates with explicit evidence posture.

const std = @import("std");
const strip = @import("strip");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var failed = false;

    // Gate 1: JSBSim out-of-process comparator (JSBSIM_CMD, python runner, or shim).
    const shim_path = "zig-out/bin/strip-jsbsim-shim";
    const jsbsim_cmd = init.environ_map.get("JSBSIM_CMD");
    const backend = try strip.adapters.jsbsim.resolveBackend(
        init.io,
        allocator,
        shim_path,
        jsbsim_cmd,
        "tools/jsbsim_atmosphere.py",
        "tools/jsbsim_cmd.sh",
    );
    var jsbsim_passed = false;
    var jsbsim_backend: []const u8 = "unavailable";
    var jsbsim_evidence: []const u8 = "unavailable";
    if (backend.kind != .unavailable) {
        jsbsim_backend = @tagName(backend.kind);
        const altitude_m = 5000.0;
        const native = try strip.weather.atmosphere.evaluate(altitude_m);
        const subprocess = try strip.adapters.jsbsim.queryAtmosphereSubprocess(
            init.io,
            allocator,
            backend,
            .{ .geopotential_altitude_m = altitude_m },
        );
        jsbsim_backend = @tagName(subprocess.backend);
        jsbsim_evidence = @tagName(strip.adapters.jsbsim.evidenceTier(subprocess.backend));
        const evaluation = try strip.adapters.jsbsim.evaluateAtmosphereGate(
            .{
                .temperature_k = native.temperature_k,
                .pressure_pa = native.pressure_pa,
                .density_kg_m3 = native.density_kg_m3,
                .speed_of_sound_mps = native.speed_of_sound_mps,
                .backend = .published_fixture,
            },
            subprocess,
        );
        jsbsim_passed = evaluation.summary.allPassed();
        if (!jsbsim_passed) failed = true;
    } else {
        failed = true;
    }

    // Gate 2a: OpenVSP pinned geometry digest conformance.
    const openvsp_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/validation/openvsp/pinned-conformance.json",
        allocator,
        .limited(128 * 1024),
    );
    defer allocator.free(openvsp_bytes);
    var openvsp_manifest = try strip.adapters.openvsp.parseManifest(allocator, openvsp_bytes);
    defer openvsp_manifest.deinit();
    const artifact = strip.adapters.openvsp.GeometryArtifact{
        .name = openvsp_manifest.value.artifact_name,
        .units = "m",
        .up_axis = "Y",
        .components = &.{
            .{ .name = "Fuselage", .kind = "Fuselage", .span_m = 8.0, .chord_m = 1.2 },
            .{ .name = "MainWing", .kind = "Wing", .span_m = 10.0, .chord_m = 1.5, .sweep_deg = 5.0 },
            .{ .name = "HTail", .kind = "Wing", .span_m = 3.0, .chord_m = 0.8, .dihedral_deg = 10.0 },
        },
    };
    const openvsp_report = try strip.adapters.openvsp.verifyConformance(
        openvsp_manifest.value,
        artifact,
    );
    if (!openvsp_report.passed) failed = true;

    // Gate 2b: OpenVSP tessellation / mesh conformance (analytic mesher; not CAD export).
    const tess_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/validation/openvsp/tessellation-conformance.json",
        allocator,
        .limited(128 * 1024),
    );
    defer allocator.free(tess_bytes);
    var tess_manifest = try std.json.parseFromSlice(
        strip.adapters.openvsp_tessellation.TessellationManifest,
        allocator,
        tess_bytes,
        .{ .ignore_unknown_fields = true, .max_value_len = 4096 },
    );
    defer tess_manifest.deinit();
    try tess_manifest.value.validate();
    const mesh = try strip.adapters.openvsp_tessellation.tessellateBoxWing(
        allocator,
        artifact,
        tess_manifest.value.segments_span,
        tess_manifest.value.segments_chord,
    );
    defer allocator.free(mesh.triangles);
    const tess_report = try strip.adapters.openvsp_tessellation.verifyTessellation(
        tess_manifest.value,
        artifact,
        mesh,
    );
    if (!tess_report.passed) failed = true;

    // Gate 3: cross-target replay fingerprint.
    const replay_fields = try strip.replay.constantAccelerationReplayFields();
    const replay_target = strip.replay.currentTarget(builtin.mode);
    const replay_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/validation/replay/rk4-cross-target.json",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(replay_bytes);
    var replay_manifest = try strip.replay.parseManifest(allocator, replay_bytes);
    defer replay_manifest.deinit();
    const replay_measurement = try strip.replay.measureAgainstManifest(
        replay_manifest.value,
        replay_target,
        replay_fields,
    );
    var replay_hex: [64]u8 = undefined;
    _ = replay_measurement.fingerprint.formatHex(&replay_hex);
    if (replay_measurement.baseline_status == .mismatched or
        replay_measurement.baseline_status == .missing)
        failed = true;

    // Gate 4a: analytic uncertainty propagation.
    const x = try strip.uncertainty.propagate.fromGaussian(1.0, .{ .mean = 1.0, .variance = 0.01 });
    const y = try strip.uncertainty.propagate.fromGaussian(2.0, .{ .mean = 2.0, .variance = 0.04 });
    const propagated = try strip.uncertainty.propagate.composeAffine(&.{ 3.0, -0.5 }, &.{ x, y }, 1.0);

    // Gate 4b: Monte Carlo calibration against analytic propagation.
    const mc = try strip.uncertainty.monte_carlo.affineMonteCarlo(
        &.{ 3.0, -0.5 },
        &.{ 1.0, 2.0 },
        &.{ 0.1, 0.2 },
        1.0,
        42,
        100_000,
    );
    const mc_sigma = @sqrt(mc.variance);
    const analytic_sigma = propagated.uncertainty.value.?;
    const mc_calibrated = @abs(mc_sigma - analytic_sigma) <= 0.05 * analytic_sigma;
    if (!mc_calibrated) failed = true;

    // Gate 4c: flight-data fusion with explicit quality gates.
    const prior = try strip.uncertainty.propagate.fromGaussian(0.0, .{ .mean = 0.0, .variance = 1.0 });
    const fused = try strip.uncertainty.flight_fusion.fuse(prior, .{
        .value = 0.5,
        .standard_uncertainty = 0.2,
        .quality = .valid,
    });
    if (!fused.observation_used or fused.fused_standard_uncertainty >= 1.0) failed = true;

    var buffer: [8192]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.proof-gates.v1\",\"jsbsim\":{{\"backend\":\"{s}\",\"evidence_tier\":\"{s}\",\"passed\":{}}},\"openvsp\":{{\"digest_passed\":{},\"tessellation_passed\":{},\"pinned_version\":\"{s}\"}},\"replay\":{{\"case\":\"{s}\",\"baseline_status\":\"{s}\",\"fingerprint_hex\":\"{s}\",\"fingerprint_matches\":{},\"max_abs_delta\":{d:.12}}},\"uncertainty\":{{\"analytic_value\":{d:.6},\"analytic_sigma\":{d:.6},\"mc_mean\":{d:.6},\"mc_sigma\":{d:.6},\"mc_calibrated\":{},\"fusion_sigma\":{d:.6}}},\"flight_qualification_claimed\":false}}\n",
        .{
            jsbsim_backend,
            jsbsim_evidence,
            jsbsim_passed,
            openvsp_report.passed,
            tess_report.passed,
            strip.adapters.openvsp.pinned_version,
            replay_measurement.case_id orelse "missing",
            @tagName(replay_measurement.baseline_status),
            replay_hex,
            replay_measurement.divergence.fingerprint_matches,
            replay_measurement.divergence.maximum_absolute_delta,
            propagated.value,
            propagated.uncertainty.value.?,
            mc.mean,
            @sqrt(mc.variance),
            mc_calibrated,
            fused.fused_standard_uncertainty,
        },
    );
    return if (failed) 1 else 0;
}
