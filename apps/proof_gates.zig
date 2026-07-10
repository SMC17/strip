//! Execute proof gates v2 with explicit evidence posture across all engineering lanes.

const std = @import("std");
const strip = @import("strip");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var failed = false;

    // Gate 1a: JSBSim atmosphere comparator.
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
    var jsbsim_atmos_passed = false;
    var jsbsim_atmos_backend: []const u8 = "unavailable";
    var jsbsim_atmos_evidence: []const u8 = "unavailable";
    if (backend.kind != .unavailable) {
        const altitude_m = 5000.0;
        const native = try strip.weather.atmosphere.evaluate(altitude_m);
        const subprocess = try strip.adapters.jsbsim.queryAtmosphereSubprocess(
            init.io,
            allocator,
            backend,
            .{ .geopotential_altitude_m = altitude_m },
        );
        jsbsim_atmos_backend = @tagName(subprocess.backend);
        jsbsim_atmos_evidence = @tagName(strip.adapters.jsbsim.evidenceTier(subprocess.backend));
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
        jsbsim_atmos_passed = evaluation.summary.allPassed();
        if (!jsbsim_atmos_passed) failed = true;
    } else failed = true;

    // Gate 1b: JSBSim fixed-wing short-horizon integration (F-16 dynamics host).
    var jsbsim_fw_passed = false;
    var jsbsim_fw_backend: []const u8 = "unavailable";
    var jsbsim_fw_evidence: []const u8 = "unavailable";
    if (backend.kind != .unavailable) {
        const fw_subprocess = try strip.adapters.jsbsim.queryFixedWingIntegrateSubprocess(
            init.io,
            allocator,
            backend,
            .{},
        );
        jsbsim_fw_backend = @tagName(fw_subprocess.backend);
        jsbsim_fw_evidence = @tagName(strip.adapters.jsbsim.evidenceTier(fw_subprocess.backend));
        const fw_bytes = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            "fixtures/validation/jsbsim/fixed-wing-integrate-comparator.json",
            allocator,
            .limited(256 * 1024),
        );
        defer allocator.free(fw_bytes);
        var fw_fixture = try strip.adapters.jsbsim.parseFixture(allocator, fw_bytes);
        defer fw_fixture.deinit();
        const fw_eval = try strip.adapters.jsbsim.evaluateFixedWingGate(fw_subprocess, fw_fixture.value);
        jsbsim_fw_passed = fw_eval.summary.allPassed();
        if (!jsbsim_fw_passed) failed = true;
    } else failed = true;

    // Gate 2a: OpenVSP pinned geometry digest.
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

    // Gate 2b: analytic tessellation conformance.
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

    // Gate 2c: OPENSP_CMD / analytic STL export conformance.
    var export_passed = false;
    var export_backend: []const u8 = "unavailable";
    const openvsp_cmd = init.environ_map.get("OPENSP_CMD");
    if (strip.adapters.openvsp_export.resolveExportCommand(init.io, openvsp_cmd, "tools/openvsp_cmd.sh")) |cmd| {
        const export_query = try strip.adapters.openvsp_export.queryExportSubprocess(
            init.io,
            allocator,
            cmd,
            "/tmp/strip-openvsp-export.stl",
        );
        export_backend = @tagName(export_query.backend);
        const export_bytes = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            "fixtures/validation/openvsp/export-conformance.json",
            allocator,
            .limited(128 * 1024),
        );
        defer allocator.free(export_bytes);
        var export_manifest = try std.json.parseFromSlice(
            strip.adapters.openvsp_export.ExportConformanceManifest,
            allocator,
            export_bytes,
            .{ .ignore_unknown_fields = true, .max_value_len = 4096 },
        );
        defer export_manifest.deinit();
        const export_report = try strip.adapters.openvsp_export.verifyExportConformance(
            export_manifest.value,
            mesh,
            export_query.backend,
        );
        export_passed = export_report.passed and
            export_query.response.triangle_count == export_manifest.value.expected_triangle_count;
        if (!export_passed) failed = true;
    } else {
        failed = true;
    }

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
    var replay_pending_count: usize = 0;
    for (replay_manifest.value.cases) |replay_case| {
        if (std.mem.eql(u8, replay_case.status, "pending")) replay_pending_count += 1;
    }
    if (replay_measurement.baseline_status == .mismatched or
        replay_measurement.baseline_status == .missing)
        failed = true;

    // Gate 4a–4c: analytic, MC, fusion.
    const x = try strip.uncertainty.propagate.fromGaussian(1.0, .{ .mean = 1.0, .variance = 0.01 });
    const y = try strip.uncertainty.propagate.fromGaussian(2.0, .{ .mean = 2.0, .variance = 0.04 });
    const propagated = try strip.uncertainty.propagate.composeAffine(&.{ 3.0, -0.5 }, &.{ x, y }, 1.0);
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
    const prior = try strip.uncertainty.propagate.fromGaussian(0.0, .{ .mean = 0.0, .variance = 1.0 });
    const fused = try strip.uncertainty.flight_fusion.fuse(prior, .{
        .value = 0.5,
        .standard_uncertainty = 0.2,
        .quality = .valid,
    });
    if (!fused.observation_used or fused.fused_standard_uncertainty >= 1.0) failed = true;

    // Gate 4d: flight-campaign calibration + holdout coverage.
    const campaign_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/validation/flight-test/synthetic-campaign.json",
        allocator,
        .limited(512 * 1024),
    );
    defer allocator.free(campaign_bytes);
    var campaign_parsed = try strip.flight_test.campaign.parseCampaign(allocator, campaign_bytes);
    defer campaign_parsed.deinit();
    const csv_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/validation/flight-test/synthetic-telemetry.csv",
        allocator,
        .limited(256 * 1024),
    );
    defer allocator.free(csv_bytes);
    const csv_rows = try strip.flight_test.telemetry_csv.loadCsv(allocator, csv_bytes);
    defer {
        for (csv_rows) |row| allocator.free(row.channel);
        allocator.free(csv_rows);
    }
    const campaign_report = try strip.uncertainty.campaign_calibration.evaluateSyntheticCampaign(
        campaign_parsed.value,
        csv_rows,
    );
    if (!campaign_report.holdout_passed) failed = true;

    // Gate 5: flight-qualification evidence framework (structure only).
    const qualification_report = try strip.flight_test.qualification.evaluateFromFixtures(
        allocator,
        init.io,
    );
    if (!qualification_report.passed) failed = true;

    var buffer: [16384]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.proof-gates.v2\",\"jsbsim\":{{\"atmosphere\":{{\"backend\":\"{s}\",\"evidence_tier\":\"{s}\",\"passed\":{}}},\"fixed_wing\":{{\"backend\":\"{s}\",\"evidence_tier\":\"{s}\",\"passed\":{}}}}},\"openvsp\":{{\"digest_passed\":{},\"tessellation_passed\":{},\"export_passed\":{},\"export_backend\":\"{s}\",\"pinned_version\":\"{s}\"}},\"replay\":{{\"case\":\"{s}\",\"baseline_status\":\"{s}\",\"pending_count\":{d},\"fingerprint_hex\":\"{s}\",\"fingerprint_matches\":{}}},\"uncertainty\":{{\"mc_calibrated\":{},\"campaign_holdout_passed\":{},\"campaign_coverage_1sigma\":{d:.6},\"fusion_sigma\":{d:.6}}},\"flight_evidence\":{{\"framework_passed\":{},\"tier\":\"software_only\",\"operational_qualification_claimed\":false}},\"flight_qualification_claimed\":false}}\n",
        .{
            jsbsim_atmos_backend,
            jsbsim_atmos_evidence,
            jsbsim_atmos_passed,
            jsbsim_fw_backend,
            jsbsim_fw_evidence,
            jsbsim_fw_passed,
            openvsp_report.passed,
            tess_report.passed,
            export_passed,
            export_backend,
            strip.adapters.openvsp.pinned_version,
            replay_measurement.case_id orelse "missing",
            @tagName(replay_measurement.baseline_status),
            replay_pending_count,
            replay_hex,
            replay_measurement.divergence.fingerprint_matches,
            mc_calibrated,
            campaign_report.holdout_passed,
            campaign_report.holdout_coverage_one_sigma,
            fused.fused_standard_uncertainty,
            qualification_report.passed,
        },
    );
    return if (failed) 1 else 0;
}
