//! Cross-target replay fingerprints and floating-point divergence measurement.
//!
//! Strict bitwise determinism across architectures is not claimed. This module
//! records canonical little-endian IEEE-754 fingerprints and reports
//! per-target divergence against pinned baselines.

const std = @import("std");
const trace = @import("../trace/mod.zig");
const dynamics_math = @import("../dynamics/math.zig");
const dynamics = @import("../dynamics/rigid_body.zig");
const mass_properties = @import("../vehicle/mass_properties.zig");

pub const TargetTriple = struct {
    arch: []const u8,
    os: []const u8,
    optimize: []const u8,
};

pub const Fingerprint = struct {
    bytes: [32]u8,

    pub fn eql(a: Fingerprint, b: Fingerprint) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }

    pub fn formatHex(self: Fingerprint, output: *[64]u8) []const u8 {
        const id = trace.ContentId{ .bytes = self.bytes };
        return id.formatHex(output);
    }
};

pub fn encodeF64Canonical(value: f64) [8]u8 {
    return @as([8]u8, @bitCast(value));
}

pub fn fingerprintFields(fields: []const f64) Fingerprint {
    var buffer: [8 * 64]u8 = undefined;
    var index: usize = 0;
    for (fields) |value| {
        const encoded = encodeF64Canonical(value);
        @memcpy(buffer[index .. index + 8], &encoded);
        index += 8;
    }
    return .{ .bytes = trace.ContentId.hash(buffer[0..index]).bytes };
}

pub const Divergence = struct {
    maximum_absolute_delta: f64,
    maximum_relative_delta: f64,
    mismatched_field_count: usize,
    fingerprint_matches: bool,

    pub fn fromFields(baseline: []const f64, observed: []const f64) error{LengthMismatch}!Divergence {
        if (baseline.len != observed.len) return error.LengthMismatch;
        var max_abs: f64 = 0;
        var max_rel: f64 = 0;
        var mismatched: usize = 0;
        for (baseline, observed) |base, obs| {
            const abs = @abs(obs - base);
            max_abs = @max(max_abs, abs);
            const denom = @max(@abs(base), 1.0e-15);
            max_rel = @max(max_rel, abs / denom);
            if (encodeF64Canonical(base)[0] != encodeF64Canonical(obs)[0] or
                encodeF64Canonical(base)[1] != encodeF64Canonical(obs)[1] or
                encodeF64Canonical(base)[2] != encodeF64Canonical(obs)[2] or
                encodeF64Canonical(base)[3] != encodeF64Canonical(obs)[3] or
                encodeF64Canonical(base)[4] != encodeF64Canonical(obs)[4] or
                encodeF64Canonical(base)[5] != encodeF64Canonical(obs)[5] or
                encodeF64Canonical(base)[6] != encodeF64Canonical(obs)[6] or
                encodeF64Canonical(base)[7] != encodeF64Canonical(obs)[7])
                mismatched += 1;
        }
        return .{
            .maximum_absolute_delta = max_abs,
            .maximum_relative_delta = max_rel,
            .mismatched_field_count = mismatched,
            .fingerprint_matches = mismatched == 0,
        };
    }
};

pub const ReplayCase = struct {
    id: []const u8,
    target: TargetTriple,
    status: []const u8 = "pinned",
    fingerprint_hex: []const u8,
    fields: []const f64,
};

pub const BaselineStatus = enum {
    matched,
    pending,
    mismatched,
    missing,
};

pub const ReplayManifest = struct {
    schema: []const u8,
    id: []const u8,
    proof_scope: []const u8,
    cases: []const ReplayCase,

    pub fn validate(self: ReplayManifest) !void {
        if (!std.mem.eql(u8, self.schema, "strip.replay-manifest.v1")) return error.UnsupportedSchema;
        if (self.id.len == 0 or self.id.len > 96) return error.InvalidId;
        if (self.proof_scope.len == 0 or self.proof_scope.len > 256) return error.InvalidProofScope;
        if (self.cases.len == 0 or self.cases.len > 32) return error.InvalidCaseCount;
        for (self.cases, 0..) |replay_case, index| {
            if (replay_case.id.len == 0 or replay_case.id.len > 96) return error.InvalidCaseId;
            if (!std.mem.eql(u8, replay_case.status, "pinned") and
                !std.mem.eql(u8, replay_case.status, "pending"))
                return error.InvalidCaseStatus;
            if (std.mem.eql(u8, replay_case.status, "pinned")) {
                if (replay_case.fingerprint_hex.len != 64) return error.InvalidFingerprint;
                for (replay_case.fingerprint_hex) |c| {
                    if (!std.ascii.isHex(c) or std.ascii.isUpper(c)) return error.InvalidFingerprint;
                }
                if (replay_case.fields.len == 0 or replay_case.fields.len > 64)
                    return error.InvalidFieldCount;
                const computed = fingerprintFields(replay_case.fields);
                var hex: [64]u8 = undefined;
                _ = computed.formatHex(&hex);
                if (!std.mem.eql(u8, &hex, replay_case.fingerprint_hex)) return error.FingerprintMismatch;
            } else if (replay_case.fingerprint_hex.len != 0 or replay_case.fields.len != 0)
                return error.PendingCaseMustBeEmpty;
            for (self.cases[0..index]) |prior| {
                if (std.mem.eql(u8, prior.id, replay_case.id)) return error.DuplicateCaseId;
            }
        }
    }
};

pub fn currentTarget(comptime optimize: std.builtin.OptimizeMode) TargetTriple {
    return .{
        .arch = @tagName(builtin.cpu.arch),
        .os = @tagName(builtin.os.tag),
        .optimize = @tagName(optimize),
    };
}

threadlocal var replay_scratch: [6]f64 = undefined;

pub fn constantAccelerationReplayFields() ![]const f64 {
    const properties = try mass_properties.MassProperties.init(
        2.0,
        dynamics_math.Vec3.zero,
        .{ .xx = 3.0, .yy = 3.0, .zz = 3.0 },
    );
    const initial = dynamics.State{
        .position_world_m = dynamics_math.Vec3.zero,
        .velocity_world_mps = .{ .x = 2.0, .y = 0.0, .z = 0.0 },
        .body_to_world = dynamics_math.Quaternion.identity,
        .angular_velocity_body_radps = dynamics_math.Vec3.zero,
    };
    const loads = dynamics.Loads{
        .wrench = .{ .force_world_n = .{ .x = 4.0, .y = 0.0, .z = 0.0 } },
        .gravity_world_mps2 = dynamics_math.Vec3.zero,
    };
    const final = try dynamics.rk4Step(
        initial,
        properties,
        loads.wrench,
        loads.gravity_world_mps2,
        0.5,
    );
    replay_scratch = .{
        final.position_world_m.x,
        final.position_world_m.y,
        final.position_world_m.z,
        final.velocity_world_mps.x,
        final.velocity_world_mps.y,
        final.velocity_world_mps.z,
    };
    return replay_scratch[0..];
}

pub fn parseManifest(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(ReplayManifest) {
    if (bytes.len > 256 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(ReplayManifest, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

pub fn measureAgainstManifest(
    manifest: ReplayManifest,
    target: TargetTriple,
    observed_fields: []const f64,
) !struct {
    case_id: ?[]const u8,
    baseline_status: BaselineStatus,
    divergence: Divergence,
    fingerprint: Fingerprint,
} {
    const observed_fp = fingerprintFields(observed_fields);
    for (manifest.cases) |replay_case| {
        if (!std.mem.eql(u8, replay_case.target.arch, target.arch)) continue;
        if (!std.mem.eql(u8, replay_case.target.os, target.os)) continue;
        if (!std.mem.eql(u8, replay_case.target.optimize, target.optimize)) continue;
        if (std.mem.eql(u8, replay_case.status, "pending")) {
            return .{
                .case_id = replay_case.id,
                .baseline_status = .pending,
                .divergence = .{
                    .maximum_absolute_delta = 0,
                    .maximum_relative_delta = 0,
                    .mismatched_field_count = 0,
                    .fingerprint_matches = false,
                },
                .fingerprint = observed_fp,
            };
        }
        const divergence = try Divergence.fromFields(replay_case.fields, observed_fields);
        return .{
            .case_id = replay_case.id,
            .baseline_status = if (divergence.fingerprint_matches) .matched else .mismatched,
            .divergence = divergence,
            .fingerprint = observed_fp,
        };
    }
    return .{
        .case_id = null,
        .baseline_status = .missing,
        .divergence = .{ .maximum_absolute_delta = 0, .maximum_relative_delta = 0, .mismatched_field_count = 0, .fingerprint_matches = false },
        .fingerprint = observed_fp,
    };
}

pub fn formatReplayCaseJson(
    replay_case_id: []const u8,
    target: TargetTriple,
    fields: []const f64,
    writer: *std.Io.Writer,
) !void {
    const fp = fingerprintFields(fields);
    var hex: [64]u8 = undefined;
    _ = fp.formatHex(&hex);
    try writer.print(
        "{{\"id\":\"{s}\",\"target\":{{\"arch\":\"{s}\",\"os\":\"{s}\",\"optimize\":\"{s}\"}},\"status\":\"pinned\",\"fingerprint_hex\":\"{s}\",\"fields\":[",
        .{ replay_case_id, target.arch, target.os, target.optimize, hex },
    );
    for (fields, 0..) |value, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.print("{d:.17}", .{value});
    }
    try writer.writeAll("]}");
}

const builtin = @import("builtin");

test "canonical f64 encoding is little-endian IEEE-754" {
    const encoded = encodeF64Canonical(1.0);
    try std.testing.expectEqual(@as(u8, 0x00), encoded[0]);
    try std.testing.expectEqual(@as(u8, 0x00), encoded[1]);
    try std.testing.expectEqual(@as(u8, 0x00), encoded[2]);
    try std.testing.expectEqual(@as(u8, 0x00), encoded[3]);
    try std.testing.expectEqual(@as(u8, 0x00), encoded[4]);
    try std.testing.expectEqual(@as(u8, 0x00), encoded[5]);
    try std.testing.expectEqual(@as(u8, 0xf0), encoded[6]);
    try std.testing.expectEqual(@as(u8, 0x3f), encoded[7]);
}

test "replay manifest matches current target constant-acceleration fingerprint" {
    const fields = try constantAccelerationReplayFields();
    const fp = fingerprintFields(fields);
    var hex: [64]u8 = undefined;
    _ = fp.formatHex(&hex);

    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/replay/rk4-cross-target.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var manifest = try parseManifest(std.testing.allocator, bytes);
    defer manifest.deinit();

    const target = currentTarget(builtin.mode);
    const measurement = try measureAgainstManifest(manifest.value, target, fields);
    try std.testing.expect(measurement.case_id != null);
    try std.testing.expectEqual(.matched, measurement.baseline_status);
    try std.testing.expect(measurement.divergence.fingerprint_matches);
}

test "divergence reports nonzero delta for perturbed fields" {
    const baseline = [_]f64{ 1.0, 2.0, 3.0 };
    const observed = [_]f64{ 1.0, 2.0000001, 3.0 };
    const divergence = try Divergence.fromFields(&baseline, &observed);
    try std.testing.expect(divergence.maximum_absolute_delta > 0.0);
}
