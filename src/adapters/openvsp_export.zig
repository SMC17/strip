//! OpenVSP mesh export conformance via OPENSP_CMD or analytic STL fallback.

const std = @import("std");
const openvsp_tessellation = @import("openvsp_tessellation.zig");
const openvsp = @import("openvsp.zig");

pub const protocol_schema = "strip.openvsp-export-protocol.v0";

pub const ExportBackend = enum {
    openvsp_cmd,
    analytic_stl_exporter,
    unavailable,
};

pub const ExportResponse = struct {
    schema: []const u8,
    backend: []const u8,
    triangle_count: u32,
    surface_area_m2: f64,
    output_path: []const u8,
    mesh_digest: ?[]const u8 = null,
    export_runtime_version: ?[]const u8 = null,
};

pub const OpenVspCmdPolicy = struct {
    min_triangle_count: u32,
    max_triangle_count: u32,
    min_surface_area_m2: f64,
    area_tolerance_fraction: f64,
};

pub const ExportConformanceManifest = struct {
    schema: []const u8,
    artifact_name: []const u8,
    expected_triangle_count: u32,
    expected_surface_area_m2: f64,
    expected_mesh_digest: []const u8,
    area_tolerance_m2: f64,
    openvsp_cmd: ?OpenVspCmdPolicy = null,

    pub fn validate(self: ExportConformanceManifest) !void {
        if (!std.mem.eql(u8, self.schema, "strip.openvsp.export-conformance.v0"))
            return error.UnsupportedSchema;
        if (self.artifact_name.len == 0 or self.artifact_name.len > 96) return error.InvalidArtifactName;
        if (!(self.expected_surface_area_m2 > 0.0)) return error.InvalidSurfaceArea;
        if (!std.mem.startsWith(u8, self.expected_mesh_digest, "sha256:") or
            self.expected_mesh_digest.len != 71)
            return error.InvalidDigest;
        if (self.openvsp_cmd) |policy| {
            if (policy.min_triangle_count == 0 or policy.max_triangle_count < policy.min_triangle_count)
                return error.InvalidTriangleBounds;
            if (!(policy.min_surface_area_m2 > 0.0) or !(policy.area_tolerance_fraction >= 0.0))
                return error.InvalidOpenVspPolicy;
        }
    }
};

pub const ExportReport = struct {
    backend: ExportBackend,
    triangle_count: u32,
    surface_area_m2: f64,
    digest_matches: bool,
    count_matches: bool,
    area_matches: bool,
    passed: bool,
};

pub fn parseBackendTag(tag: []const u8) ExportBackend {
    if (std.mem.eql(u8, tag, "openvsp_cmd")) return .openvsp_cmd;
    if (std.mem.eql(u8, tag, "analytic_stl_exporter")) return .analytic_stl_exporter;
    return .unavailable;
}

pub fn resolveExportCommand(
    io: std.Io,
    openvsp_cmd: ?[]const u8,
    default_cmd: ?[]const u8,
) ?[]const u8 {
    if (openvsp_cmd) |cmd| {
        if (cmd.len > 0 and fileExecutable(io, cmd)) return cmd;
    }
    if (default_cmd) |cmd| {
        if (cmd.len > 0 and fileExecutable(io, cmd)) return cmd;
    }
    return null;
}

fn fileExecutable(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

pub fn queryExportSubprocess(
    io: std.Io,
    gpa: std.mem.Allocator,
    command: []const u8,
    output_path: []const u8,
) !struct { response: ExportResponse, backend: ExportBackend } {
    const request = try std.fmt.allocPrint(gpa, "{{\"schema\":\"{s}\",\"output_path\":\"{s}\"}}\n", .{
        protocol_schema, output_path,
    });
    defer gpa.free(request);

    var child = try std.process.spawn(io, .{
        .argv = &.{ command, "export" },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
    });
    const stdin = child.stdin orelse return error.MissingPipe;
    var stdin_writer_buffer: [512]u8 = undefined;
    var stdin_writer = stdin.writer(io, &stdin_writer_buffer);
    try stdin_writer.interface.writeAll(request);
    try stdin_writer.interface.flush();

    const stdout = child.stdout orelse return error.MissingPipe;
    var stdout_reader_buffer: [8192]u8 = undefined;
    var stdout_reader = stdout.reader(io, &stdout_reader_buffer);
    var response_line: []const u8 = "";
    while (true) {
        const line = try stdout_reader.interface.takeDelimiterInclusive('\n');
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len > 0 and trimmed[0] == '{') {
            response_line = trimmed;
            break;
        }
    }
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.SubprocessFailed,
        else => return error.SubprocessFailed,
    }

    var parsed = try std.json.parseFromSlice(ExportResponse, gpa, response_line, .{
        .ignore_unknown_fields = true,
        .max_value_len = 512,
    });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.schema, protocol_schema)) return error.InvalidResponseSchema;
    const backend = parseBackendTag(parsed.value.backend);
    return .{ .response = parsed.value, .backend = backend };
}

pub fn parseAsciiStl(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !openvsp_tessellation.Mesh {
    const end = std.mem.indexOfScalar(u8, path, 0) orelse path.len;
    const trimmed_path = std.mem.trim(u8, path[0..end], " \t\r\n");
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, trimmed_path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);

    var triangles = std.ArrayList(openvsp_tessellation.Triangle).initCapacity(allocator, 256) catch return error.OutOfMemory;
    errdefer triangles.deinit(allocator);

    var current: [3]openvsp_tessellation.Vec3 = undefined;
    var vertex_count: usize = 0;

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "vertex")) continue;
        var iter = std.mem.splitScalar(u8, line, ' ');
        _ = iter.next();
        const x_text = iter.next() orelse continue;
        const y_text = iter.next() orelse continue;
        const z_text = iter.next() orelse continue;
        current[vertex_count] = .{
            .x = try std.fmt.parseFloat(f64, x_text),
            .y = try std.fmt.parseFloat(f64, y_text),
            .z = try std.fmt.parseFloat(f64, z_text),
        };
        vertex_count += 1;
        if (vertex_count == 3) {
            try triangles.append(allocator, .{ .a = current[0], .b = current[1], .c = current[2] });
            vertex_count = 0;
        }
    }
    if (triangles.items.len == 0) return error.EmptyMesh;
    return .{ .triangles = try triangles.toOwnedSlice(allocator) };
}

pub fn verifyExportConformance(
    manifest: ExportConformanceManifest,
    mesh: openvsp_tessellation.Mesh,
    backend: ExportBackend,
) !ExportReport {
    try manifest.validate();
    const digest = try mesh.digest();
    var digest_text: [71]u8 = undefined;
    @memcpy(digest_text[0..7], "sha256:");
    @memcpy(digest_text[7..], digest.hex[0..64]);
    const count = @as(u32, @intCast(mesh.triangleCount()));
    const area = mesh.surfaceArea();

    return switch (backend) {
        .openvsp_cmd => verifyOpenVspCmdConformance(manifest, &digest_text, count, area),
        .analytic_stl_exporter => verifyAnalyticConformance(manifest, &digest_text, count, area),
        .unavailable => .{
            .backend = backend,
            .triangle_count = count,
            .surface_area_m2 = area,
            .digest_matches = false,
            .count_matches = false,
            .area_matches = false,
            .passed = false,
        },
    };
}

fn verifyAnalyticConformance(
    manifest: ExportConformanceManifest,
    digest_text: *const [71]u8,
    count: u32,
    area: f64,
) ExportReport {
    const digest_matches = std.mem.eql(u8, digest_text, manifest.expected_mesh_digest);
    const count_matches = count == manifest.expected_triangle_count;
    const area_matches = @abs(area - manifest.expected_surface_area_m2) <= manifest.area_tolerance_m2;
    const passed = digest_matches and count_matches and area_matches;
    return .{
        .backend = .analytic_stl_exporter,
        .triangle_count = count,
        .surface_area_m2 = area,
        .digest_matches = digest_matches,
        .count_matches = count_matches,
        .area_matches = area_matches,
        .passed = passed,
    };
}

fn verifyOpenVspCmdConformance(
    manifest: ExportConformanceManifest,
    digest_text: *const [71]u8,
    count: u32,
    area: f64,
) ExportReport {
    const policy = manifest.openvsp_cmd orelse {
        return .{
            .backend = .openvsp_cmd,
            .triangle_count = count,
            .surface_area_m2 = area,
            .digest_matches = false,
            .count_matches = false,
            .area_matches = false,
            .passed = false,
        };
    };
    const count_matches = count >= policy.min_triangle_count and count <= policy.max_triangle_count;
    const area_matches = area >= policy.min_surface_area_m2 and
        @abs(area - manifest.expected_surface_area_m2) <=
            policy.area_tolerance_fraction * manifest.expected_surface_area_m2;
    const passed = count_matches and area_matches;
    return .{
        .backend = .openvsp_cmd,
        .triangle_count = count,
        .surface_area_m2 = area,
        .digest_matches = std.mem.eql(u8, digest_text, manifest.expected_mesh_digest),
        .count_matches = count_matches,
        .area_matches = area_matches,
        .passed = passed,
    };
}

test "export conformance manifest validates" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/openvsp/export-conformance.json",
        std.testing.allocator,
        .limited(128 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(ExportConformanceManifest, std.testing.allocator, bytes, .{
        .ignore_unknown_fields = true,
        .max_value_len = 4096,
    });
    defer parsed.deinit();
    try parsed.value.validate();
}

test "ascii STL parser reads exported mesh file" {
    const cmd = resolveExportCommand(std.testing.io, null, "tools/openvsp_cmd.sh") orelse
        return error.SkipZigTest;
    const output_path = "openvsp-export-test.stl";
    _ = try queryExportSubprocess(
        std.testing.io,
        std.testing.allocator,
        cmd,
        output_path,
    );
    const mesh = try parseAsciiStl(std.testing.allocator, std.testing.io, output_path);
    defer std.testing.allocator.free(mesh.triangles);
    try std.testing.expect(mesh.triangleCount() > 0);
}
