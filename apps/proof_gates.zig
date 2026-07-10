//! Execute the four proof gates with explicit evidence posture.

const std = @import("std");
const strip = @import("strip");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;

    // Gate 1: JSBSim out-of-process comparator (shim or JSBSIM_CMD).
    const shim_path = "zig-out/bin/strip-jsbsim-shim";
    const jsbsim_cmd = init.environ_map.get("JSBSIM_CMD");
    const backend = try strip.adapters.jsbsim.resolveBackend(init.io, allocator, shim_path, jsbsim_cmd);
    var jsbsim_passed = false;
    var jsbsim_backend: []const u8 = "unavailable";
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
        const summary = try strip.adapters.jsbsim.compareAtmosphere(
            .{
                .temperature_k = native.temperature_k,
                .pressure_pa = native.pressure_pa,
                .density_kg_m3 = native.density_kg_m3,
                .speed_of_sound_mps = native.speed_of_sound_mps,
                .backend = .published_fixture,
            },
            subprocess,
            .{ .absolute_tolerance = 1e-6, .relative_tolerance = 1e-9 },
        );
        jsbsim_passed = summary.allPassed();
    }

    // Gate 2: OpenVSP pinned conformance.
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

    // Gate 4: uncertainty propagation.
    const x = try strip.uncertainty.propagate.fromGaussian(1.0, .{ .mean = 1.0, .variance = 0.01 });
    const y = try strip.uncertainty.propagate.fromGaussian(2.0, .{ .mean = 2.0, .variance = 0.04 });
    const propagated = try strip.uncertainty.propagate.composeAffine(&.{ 3.0, -0.5 }, &.{ x, y }, 1.0);

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.proof-gates.v0\",\"jsbsim\":{{\"backend\":\"{s}\",\"passed\":{}}},\"openvsp\":{{\"pinned_version\":\"{s}\",\"passed\":{}}},\"replay\":{{\"case\":\"{s}\",\"fingerprint_matches\":{},\"max_abs_delta\":{d:.12}}},\"uncertainty\":{{\"value\":{d:.6},\"sigma\":{d:.6}}},\"flight_qualification_claimed\":false}}\n",
        .{
            jsbsim_backend,
            jsbsim_passed,
            strip.adapters.openvsp.pinned_version,
            openvsp_report.passed,
            replay_measurement.case_id orelse "missing",
            replay_measurement.divergence.fingerprint_matches,
            replay_measurement.divergence.maximum_absolute_delta,
            propagated.value,
            propagated.uncertainty.value.?,
        },
    );
    return 0;
}
