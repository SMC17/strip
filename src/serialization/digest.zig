//! Content identifiers used by manifests and serialized artifacts.

const std = @import("std");

pub const Algorithm = enum {
    sha256,
};

pub const Identifier = struct {
    algorithm: Algorithm,
    hex: [64]u8,

    pub fn format(self: Identifier, writer: *std.Io.Writer) !void {
        try writer.print("{s}:{s}", .{ @tagName(self.algorithm), self.hex });
    }
};

pub fn sha256(bytes: []const u8) Identifier {
    var raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &raw, .{});

    const alphabet = "0123456789abcdef";
    var hex: [64]u8 = undefined;
    for (raw, 0..) |byte, i| {
        hex[i * 2] = alphabet[byte >> 4];
        hex[i * 2 + 1] = alphabet[byte & 0x0f];
    }
    return .{ .algorithm = .sha256, .hex = hex };
}

test "sha256 identifiers are stable and lowercase" {
    const id = sha256("abc");
    try std.testing.expectEqualStrings(
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        &id.hex,
    );
}
