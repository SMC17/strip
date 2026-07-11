//! Parametric tessellation and mesh conformance for pinned OpenVSP geometry.
//!
//! This is a bounded analytic mesher for conformance testing. It does not
//! invoke OpenVSP. When `OPENSP_CMD` is set, subprocess export may be added
//! in a later lane; mesh digest conformance is the current executable gate.

const std = @import("std");
const serialization = @import("../serialization/digest.zig");
const openvsp = @import("openvsp.zig");

pub const Vec3 = struct { x: f64, y: f64, z: f64 };
pub const Triangle = struct { a: Vec3, b: Vec3, c: Vec3 };

pub const Mesh = struct {
    triangles: []const Triangle,

    pub fn triangleCount(self: Mesh) usize {
        return self.triangles.len;
    }

    pub fn surfaceArea(self: Mesh) f64 {
        var area: f64 = 0;
        for (self.triangles) |tri| {
            const ab = Vec3{
                .x = tri.b.x - tri.a.x,
                .y = tri.b.y - tri.a.y,
                .z = tri.b.z - tri.a.z,
            };
            const ac = Vec3{
                .x = tri.c.x - tri.a.x,
                .y = tri.c.y - tri.a.y,
                .z = tri.c.z - tri.a.z,
            };
            const cx = ab.y * ac.z - ab.z * ac.y;
            const cy = ab.z * ac.x - ab.x * ac.z;
            const cz = ab.x * ac.y - ab.y * ac.x;
            area += 0.5 * @sqrt(cx * cx + cy * cy + cz * cz);
        }
        return area;
    }

    fn vertexKey(v: Vec3) u64 {
        const scale: f64 = 1_000_000.0;
        const ix = @as(i64, @intFromFloat(@round(v.x * scale)));
        const iy = @as(i64, @intFromFloat(@round(v.y * scale)));
        const iz = @as(i64, @intFromFloat(@round(v.z * scale)));
        var buf: [24]u8 = undefined;
        @memcpy(buf[0..8], std.mem.asBytes(&ix));
        @memcpy(buf[8..16], std.mem.asBytes(&iy));
        @memcpy(buf[16..24], std.mem.asBytes(&iz));
        return std.hash.Wyhash.hash(0, buf[0..24]);
    }

    fn edgeKey(a: Vec3, b: Vec3) u64 {
        const ka = vertexKey(a);
        const kb = vertexKey(b);
        var pair = [_]u64{ ka, kb };
        if (ka > kb) std.mem.swap(u64, &pair[0], &pair[1]);
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&pair));
    }

    pub fn isWatertight(self: Mesh) bool {
        var counts = std.AutoHashMap(u64, u32).init(std.heap.page_allocator);
        defer counts.deinit();
        for (self.triangles) |tri| {
            const edges = [_]u64{
                edgeKey(tri.a, tri.b),
                edgeKey(tri.b, tri.c),
                edgeKey(tri.c, tri.a),
            };
            for (edges) |key| {
                const entry = counts.getOrPut(key) catch return false;
                if (!entry.found_existing) entry.value_ptr.* = 0;
                entry.value_ptr.* += 1;
            }
        }
        var it = counts.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.* != 2) return false;
        }
        return self.triangles.len > 0;
    }

    pub fn canonicalBytes(self: Mesh, buffer: []u8) ![]const u8 {
        var index: usize = 0;
        for (self.triangles) |tri| {
            inline for (.{ tri.a, tri.b, tri.c }) |vertex| {
                inline for (.{ vertex.x, vertex.y, vertex.z }) |coord| {
                    var tmp: [32]u8 = undefined;
                    const text = try std.fmt.bufPrint(&tmp, "{d:.9}|", .{coord});
                    if (index + text.len > buffer.len) return error.BufferTooSmall;
                    @memcpy(buffer[index .. index + text.len], text);
                    index += text.len;
                }
            }
        }
        return buffer[0..index];
    }

    pub fn digest(self: Mesh) !serialization.Identifier {
        const needed = self.triangles.len * 9 * 16 + 256;
        const buffer = try std.heap.page_allocator.alloc(u8, @max(needed, 4096));
        defer std.heap.page_allocator.free(buffer);
        return serialization.sha256(try self.canonicalBytes(buffer));
    }
};

pub fn tessellateBoxWing(
    allocator: std.mem.Allocator,
    artifact: openvsp.GeometryArtifact,
    segments_span: usize,
    segments_chord: usize,
) !Mesh {
    try artifact.validate();
    if (segments_span < 2 or segments_span > 64 or segments_chord < 2 or segments_chord > 64)
        return error.InvalidSegmentation;

    var total: usize = 0;
    for (artifact.components) |_| {
        total += 2 * segments_span * segments_chord;
    }
    const triangles = try allocator.alloc(Triangle, total);
    errdefer allocator.free(triangles);

    var index: usize = 0;
    for (artifact.components) |component| {
        const half_span = 0.5 * component.span_m;
        const chord = component.chord_m;
        for (0..segments_span) |si| {
            const y0 = -half_span + @as(f64, @floatFromInt(si)) * component.span_m / @as(f64, @floatFromInt(segments_span));
            const y1 = -half_span + @as(f64, @floatFromInt(si + 1)) * component.span_m / @as(f64, @floatFromInt(segments_span));
            for (0..segments_chord) |ci| {
                const x0 = @as(f64, @floatFromInt(ci)) * chord / @as(f64, @floatFromInt(segments_chord));
                const x1 = @as(f64, @floatFromInt(ci + 1)) * chord / @as(f64, @floatFromInt(segments_chord));
                const p00 = Vec3{ .x = x0, .y = y0, .z = 0 };
                const p10 = Vec3{ .x = x1, .y = y0, .z = 0 };
                const p01 = Vec3{ .x = x0, .y = y1, .z = 0 };
                const p11 = Vec3{ .x = x1, .y = y1, .z = 0 };
                triangles[index] = .{ .a = p00, .b = p10, .c = p11 };
                triangles[index + 1] = .{ .a = p00, .b = p11, .c = p01 };
                index += 2;
            }
        }
    }
    return .{ .triangles = triangles };
}

pub const TessellationManifest = struct {
    schema: []const u8,
    segments_span: usize,
    segments_chord: usize,
    expected_triangle_count: u32,
    expected_surface_area_m2: f64,
    expected_mesh_digest: []const u8,
    watertight_required: bool,

    pub fn validate(self: TessellationManifest) !void {
        if (!std.mem.eql(u8, self.schema, "strip.openvsp.tessellation.v0"))
            return error.UnsupportedSchema;
        if (self.segments_span < 2 or self.segments_span > 64 or
            self.segments_chord < 2 or self.segments_chord > 64)
            return error.InvalidSegmentation;
        if (!std.mem.startsWith(u8, self.expected_mesh_digest, "sha256:") or
            self.expected_mesh_digest.len != 71)
            return error.InvalidDigest;
        if (!(self.expected_surface_area_m2 > 0.0) or !std.math.isFinite(self.expected_surface_area_m2))
            return error.InvalidSurfaceArea;
    }
};

pub const TessellationReport = struct {
    triangle_count: u32,
    surface_area_m2: f64,
    mesh_digest: serialization.Identifier,
    digest_matches: bool,
    count_matches: bool,
    passed: bool,
};

pub fn verifyTessellation(
    manifest: TessellationManifest,
    _: openvsp.GeometryArtifact,
    mesh: Mesh,
) !TessellationReport {
    try manifest.validate();
    const digest = try mesh.digest();
    var digest_text: [71]u8 = undefined;
    @memcpy(digest_text[0..7], "sha256:");
    @memcpy(digest_text[7..], digest.hex[0..64]);
    const digest_matches = std.mem.eql(u8, &digest_text, manifest.expected_mesh_digest);
    const count = @as(u32, @intCast(mesh.triangleCount()));
    const count_matches = count == manifest.expected_triangle_count;
    const area = mesh.surfaceArea();
    const area_matches = @abs(area - manifest.expected_surface_area_m2) <=
        @max(1e-6, 1e-6 * manifest.expected_surface_area_m2);
    const watertight_matches = !manifest.watertight_required or mesh.isWatertight();
    return .{
        .triangle_count = count,
        .surface_area_m2 = area,
        .mesh_digest = digest,
        .digest_matches = digest_matches,
        .count_matches = count_matches,
        .passed = digest_matches and count_matches and area_matches and watertight_matches,
    };
}

test "reference box-wing tessellation matches pinned manifest" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/openvsp/tessellation-conformance.json",
        std.testing.allocator,
        .limited(128 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var manifest = try std.json.parseFromSlice(TessellationManifest, std.testing.allocator, bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    defer manifest.deinit();
    try manifest.value.validate();

    const artifact = openvsp.GeometryArtifact{
        .name = "reference-box-wing",
        .units = "m",
        .up_axis = "Y",
        .components = &.{
            .{ .name = "Fuselage", .kind = "Fuselage", .span_m = 8.0, .chord_m = 1.2 },
            .{ .name = "MainWing", .kind = "Wing", .span_m = 10.0, .chord_m = 1.5, .sweep_deg = 5.0 },
            .{ .name = "HTail", .kind = "Wing", .span_m = 3.0, .chord_m = 0.8, .dihedral_deg = 10.0 },
        },
    };
    const mesh = try tessellateBoxWing(
        std.testing.allocator,
        artifact,
        manifest.value.segments_span,
        manifest.value.segments_chord,
    );
    defer std.testing.allocator.free(mesh.triangles);
    const report = try verifyTessellation(manifest.value, artifact, mesh);
    try std.testing.expect(report.passed);
}
