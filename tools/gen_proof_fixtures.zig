//! Generate pinned digests for proof-gate fixtures.
const std = @import("std");
const strip = @import("strip");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !u8 {
    const fields = try strip.replay.constantAccelerationReplayFields();
    const fp = strip.replay.fingerprintFields(fields);
    var replay_hex: [64]u8 = undefined;
    _ = fp.formatHex(&replay_hex);

    const artifact = strip.adapters.openvsp.GeometryArtifact{
        .name = "reference-box-wing",
        .units = "m",
        .up_axis = "Y",
        .components = &.{
            .{ .name = "Fuselage", .kind = "Fuselage", .span_m = 8.0, .chord_m = 1.2 },
            .{ .name = "MainWing", .kind = "Wing", .span_m = 10.0, .chord_m = 1.5, .sweep_deg = 5.0 },
            .{ .name = "HTail", .kind = "Wing", .span_m = 3.0, .chord_m = 0.8, .dihedral_deg = 10.0 },
        },
    };
    const digest = try artifact.digest();

    var mesh = try strip.adapters.openvsp_tessellation.tessellateBoxWing(
        init.gpa,
        artifact,
        4,
        4,
    );
    defer init.gpa.free(mesh.triangles);
    const mesh_digest = try mesh.digest();
    const mesh_area = mesh.surfaceArea();
    const mesh_count = mesh.triangleCount();

    var buffer: [8192]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print("replay_fields=", .{});
    for (fields, 0..) |value, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.print("{d:.17}", .{value});
    }
    try writer.print("\nreplay_fingerprint={s}\n", .{replay_hex});
    try writer.print("target_arch={s}\n", .{@tagName(builtin.cpu.arch)});
    try writer.print("target_os={s}\n", .{@tagName(builtin.os.tag)});
    try writer.print("target_optimize={s}\n", .{@tagName(builtin.mode)});
    try writer.print("openvsp_digest=sha256:{s}\n", .{digest.hex});
    try writer.print("tessellation_segments_span=4\n", .{});
    try writer.print("tessellation_segments_chord=4\n", .{});
    try writer.print("tessellation_triangle_count={d}\n", .{mesh_count});
    try writer.print("tessellation_surface_area_m2={d:.12}\n", .{mesh_area});
    try writer.print("tessellation_mesh_digest=sha256:{s}\n", .{mesh_digest.hex});
    return 0;
}
