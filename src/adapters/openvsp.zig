//! Pinned OpenVSP geometry adapter with digest conformance checks.
//!
//! No OpenVSP runtime is linked. Conformance verifies canonical geometry
//! descriptions against a pinned release manifest and expected digests.

const std = @import("std");
const serialization = @import("../serialization/root.zig");

pub const pinned_product = "OpenVSP";
pub const pinned_version = "3.42.0";
pub const pinned_schema = "strip.openvsp.conformance.v0";

pub const Component = struct {
    name: []const u8,
    kind: []const u8,
    span_m: f64,
    chord_m: f64,
    sweep_deg: f64 = 0,
    dihedral_deg: f64 = 0,
};

pub const GeometryArtifact = struct {
    name: []const u8,
    units: []const u8,
    up_axis: []const u8,
    components: []const Component,

    pub fn validate(self: GeometryArtifact) !void {
        if (self.name.len == 0 or self.name.len > 96) return error.InvalidName;
        if (!std.mem.eql(u8, self.units, "m")) return error.InvalidUnits;
        if (!std.mem.eql(u8, self.up_axis, "Y")) return error.InvalidUpAxis;
        if (self.components.len == 0 or self.components.len > 64) return error.InvalidComponentCount;
        for (self.components) |component| {
            if (component.name.len == 0 or component.name.len > 64) return error.InvalidComponentName;
            if (component.kind.len == 0 or component.kind.len > 32) return error.InvalidComponentKind;
            inline for (.{ component.span_m, component.chord_m, component.sweep_deg, component.dihedral_deg }) |value| {
                if (!std.math.isFinite(value)) return error.NonFiniteGeometry;
            }
            if (!(component.span_m > 0) or !(component.chord_m > 0)) return error.NonPositiveGeometry;
        }
    }

    pub fn canonicalBytes(self: GeometryArtifact, buffer: []u8) ![]const u8 {
        var index: usize = 0;
        const write = struct {
            fn append(buf: []u8, pos: *usize, slice: []const u8) !void {
                if (pos.* + slice.len > buf.len) return error.BufferTooSmall;
                @memcpy(buf[pos.* .. pos.* + slice.len], slice);
                pos.* += slice.len;
            }
            fn appendF64(buf: []u8, pos: *usize, value: f64) !void {
                var tmp: [32]u8 = undefined;
                const text = try std.fmt.bufPrint(&tmp, "{d:.12}|", .{value});
                try append(buf, pos, text);
            }
        };

        try write.append(buffer, &index, self.name);
        try write.append(buffer, &index, "|");
        try write.append(buffer, &index, self.units);
        try write.append(buffer, &index, "|");
        try write.append(buffer, &index, self.up_axis);
        try write.append(buffer, &index, "|");
        for (self.components) |component| {
            try write.append(buffer, &index, component.name);
            try write.append(buffer, &index, "|");
            try write.append(buffer, &index, component.kind);
            try write.append(buffer, &index, "|");
            try write.appendF64(buffer, &index, component.span_m);
            try write.appendF64(buffer, &index, component.chord_m);
            try write.appendF64(buffer, &index, component.sweep_deg);
            try write.appendF64(buffer, &index, component.dihedral_deg);
        }
        return buffer[0..index];
    }

    pub fn digest(self: GeometryArtifact) serialization.digest.Identifier {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        serialization.canonical_encoder.appendText(&hasher, self.name);
        serialization.canonical_encoder.appendText(&hasher, "|");
        serialization.canonical_encoder.appendText(&hasher, self.units);
        serialization.canonical_encoder.appendText(&hasher, "|");
        serialization.canonical_encoder.appendText(&hasher, self.up_axis);
        serialization.canonical_encoder.appendText(&hasher, "|");
        for (self.components) |component| {
            serialization.canonical_encoder.appendText(&hasher, component.name);
            serialization.canonical_encoder.appendText(&hasher, "|");
            serialization.canonical_encoder.appendText(&hasher, component.kind);
            serialization.canonical_encoder.appendText(&hasher, "|");
            serialization.canonical_encoder.appendGeometryCoord(&hasher, component.span_m);
            serialization.canonical_encoder.appendGeometryCoord(&hasher, component.chord_m);
            serialization.canonical_encoder.appendGeometryCoord(&hasher, component.sweep_deg);
            serialization.canonical_encoder.appendGeometryCoord(&hasher, component.dihedral_deg);
        }
        return serialization.canonical_encoder.finishHasher(&hasher);
    }
};

pub const ConformanceManifest = struct {
    schema: []const u8,
    product: []const u8,
    version: []const u8,
    artifact_name: []const u8,
    expected_component_count: u32,
    expected_geometry_digest: []const u8,
    tessellation_tolerance_m: f64,
    limitations: []const []const u8,

    pub fn validate(self: ConformanceManifest) !void {
        if (!std.mem.eql(u8, self.schema, pinned_schema)) return error.UnsupportedSchema;
        if (!std.mem.eql(u8, self.product, pinned_product)) return error.UnsupportedProduct;
        if (!std.mem.eql(u8, self.version, pinned_version)) return error.UnsupportedVersion;
        if (self.artifact_name.len == 0 or self.artifact_name.len > 96) return error.InvalidArtifactName;
        if (!std.mem.startsWith(u8, self.expected_geometry_digest, "sha256:") or
            self.expected_geometry_digest.len != 71)
            return error.InvalidDigest;
        if (!(self.tessellation_tolerance_m > 0.0) or !std.math.isFinite(self.tessellation_tolerance_m))
            return error.InvalidTolerance;
        if (self.limitations.len == 0 or self.limitations.len > 16) return error.InvalidLimitations;
        for (self.limitations) |limitation| {
            if (limitation.len == 0 or limitation.len > 512) return error.InvalidLimitation;
        }
    }
};

pub const ConformanceReport = struct {
    component_count: u32,
    geometry_digest: serialization.digest.Identifier,
    digest_matches: bool,
    version_matches: bool,
    passed: bool,
};

pub fn verifyConformance(
    manifest: ConformanceManifest,
    artifact: GeometryArtifact,
) !ConformanceReport {
    try manifest.validate();
    try artifact.validate();
    if (!std.mem.eql(u8, artifact.name, manifest.artifact_name)) return error.ArtifactNameMismatch;

    const digest = artifact.digest();
    var digest_text: [71]u8 = undefined;
    @memcpy(digest_text[0..7], "sha256:");
    @memcpy(digest_text[7..], digest.hex[0..64]);

    const digest_matches = std.mem.eql(u8, &digest_text, manifest.expected_geometry_digest);
    const count_matches = @as(u32, @intCast(artifact.components.len)) == manifest.expected_component_count;
    return .{
        .component_count = @intCast(artifact.components.len),
        .geometry_digest = digest,
        .digest_matches = digest_matches,
        .version_matches = true,
        .passed = digest_matches and count_matches,
    };
}

pub const Availability = union(enum) {
    unavailable: []const u8,
    pinned_manifest: ConformanceManifest,
};

pub fn defaultAvailability() Availability {
    return .{ .unavailable = "OpenVSP runtime not linked; conformance uses pinned manifest only" };
}

pub fn parseManifest(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(ConformanceManifest) {
    if (bytes.len > 128 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(ConformanceManifest, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

test "pinned OpenVSP conformance manifest verifies reference geometry" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/openvsp/pinned-conformance.json",
        std.testing.allocator,
        .limited(128 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var manifest = try parseManifest(std.testing.allocator, bytes);
    defer manifest.deinit();

    const artifact = GeometryArtifact{
        .name = manifest.value.artifact_name,
        .units = "m",
        .up_axis = "Y",
        .components = &.{
            .{ .name = "Fuselage", .kind = "Fuselage", .span_m = 8.0, .chord_m = 1.2 },
            .{ .name = "MainWing", .kind = "Wing", .span_m = 10.0, .chord_m = 1.5, .sweep_deg = 5.0 },
            .{ .name = "HTail", .kind = "Wing", .span_m = 3.0, .chord_m = 0.8, .dihedral_deg = 10.0 },
        },
    };
    const report = try verifyConformance(manifest.value, artifact);
    try std.testing.expect(report.passed);
    try std.testing.expect(report.digest_matches);
    try std.testing.expectEqual(@as(u32, 3), report.component_count);
}

test "geometry digest changes when span changes" {
    const base = GeometryArtifact{
        .name = "reference-box-wing",
        .units = "m",
        .up_axis = "Y",
        .components = &.{.{ .name = "MainWing", .kind = "Wing", .span_m = 10.0, .chord_m = 1.5 }},
    };
    const mutated = GeometryArtifact{
        .name = "reference-box-wing",
        .units = "m",
        .up_axis = "Y",
        .components = &.{.{ .name = "MainWing", .kind = "Wing", .span_m = 10.1, .chord_m = 1.5 }},
    };
    const base_digest = base.digest();
    const mutated_digest = mutated.digest();
    try std.testing.expect(!std.mem.eql(u8, &base_digest.hex, &mutated_digest.hex));
}
