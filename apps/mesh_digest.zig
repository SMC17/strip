//! Print Strip mesh digest for an ASCII STL file.
const std = @import("std");
const strip = @import("strip");

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const path = it.next() orelse return 1;
    const mesh = try strip.adapters.openvsp_export.parseAsciiStl(allocator, init.io, path);
    defer allocator.free(mesh.triangles);
    const digest = mesh.digest();
    var buffer: [256]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print("sha256:{s}\ntriangles={d}\narea={d:.12}\n", .{
        digest.hex,
        mesh.triangleCount(),
        mesh.surfaceArea(),
    });
    return 0;
}
