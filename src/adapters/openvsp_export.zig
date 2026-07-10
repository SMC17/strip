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
};

pub const ExportConformanceManifest = struct {
    schema: []const u8,
    artifact_name: []const u8,
    expected_triangle_count: u32,
    expected_surface_area_m2: f64,
    expected_mesh_digest: []const u8,
    area_tolerance_m2: f64,

    pub fn validate(self: ExportConformanceManifest) !void {
        if (!std.mem.eql(u8, self.schema, "strip.openvsp.export-conformance.v0"))
            return error.UnsupportedSchema;
        if (self.artifact_name.len == 0 or self.artifact_name.len > 96) return error.InvalidArtifactName;
        if (!(self.expected_surface_area_m2 > 0.0)) return error.InvalidSurfaceArea;
        if (!std.mem.startsWith(u8, self.expected_mesh_digest, "sha256:") or
            self.expected_mesh_digest.len != 71)
            return error.InvalidDigest;
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
    var stdout_reader_buffer: [4096]u8 = undefined;
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
    const digest_matches = std.mem.eql(u8, &digest_text, manifest.expected_mesh_digest);
    const count = @as(u32, @intCast(mesh.triangleCount()));
    const count_matches = count == manifest.expected_triangle_count;
    const area = mesh.surfaceArea();
    const area_matches = @abs(area - manifest.expected_surface_area_m2) <= manifest.area_tolerance_m2;
    const passed = digest_matches and count_matches and area_matches;
    return .{
        .backend = backend,
        .triangle_count = count,
        .surface_area_m2 = area,
        .digest_matches = digest_matches,
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
