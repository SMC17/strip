//! Streaming canonical encoders that hash directly without materializing buffers.

const std = @import("std");
const digest = @import("digest.zig");

pub const CoordPrecision = enum { mesh, geometry };

fn appendCoord(hasher: *std.crypto.hash.sha2.Sha256, value: f64, precision: CoordPrecision) void {
    var tmp: [32]u8 = undefined;
    const text = switch (precision) {
        .mesh => std.fmt.bufPrint(&tmp, "{d:.9}|", .{value}) catch unreachable,
        .geometry => std.fmt.bufPrint(&tmp, "{d:.12}|", .{value}) catch unreachable,
    };
    hasher.update(text);
}

fn appendSlice(hasher: *std.crypto.hash.sha2.Sha256, slice: []const u8) void {
    hasher.update(slice);
}

pub fn appendMeshCoord(hasher: *std.crypto.hash.sha2.Sha256, value: f64) void {
    appendCoord(hasher, value, .mesh);
}

pub fn appendGeometryCoord(hasher: *std.crypto.hash.sha2.Sha256, value: f64) void {
    appendCoord(hasher, value, .geometry);
}

pub fn appendText(hasher: *std.crypto.hash.sha2.Sha256, slice: []const u8) void {
    appendSlice(hasher, slice);
}

pub fn finishHasher(hasher: *std.crypto.hash.sha2.Sha256) digest.Identifier {
    var raw: [32]u8 = undefined;
    hasher.final(&raw);
    const alphabet = "0123456789abcdef";
    var hex: [64]u8 = undefined;
    for (raw, 0..) |byte, i| {
        hex[i * 2] = alphabet[byte >> 4];
        hex[i * 2 + 1] = alphabet[byte & 0x0f];
    }
    return .{ .algorithm = .sha256, .hex = hex };
}

test "streaming mesh hash matches buffered canonical digest" {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    const coords = [_]f64{ 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0 };
    for (coords) |coord| appendMeshCoord(&hasher, coord);
    const streamed = finishHasher(&hasher);

    var buffer: [256]u8 = undefined;
    var index: usize = 0;
    for (coords) |coord| {
        const text = try std.fmt.bufPrint(buffer[index..], "{d:.9}|", .{coord});
        index += text.len;
    }
    const buffered = digest.sha256(buffer[0..index]);
    try std.testing.expectEqualStrings(&buffered.hex, &streamed.hex);
}
