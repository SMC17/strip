//! Load Google API key from env or private workstation file (never from git).

const std = @import("std");

pub const default_key_path = "/home/stax/.local/state/stax/google-api-key";

/// Returns env key if set; otherwise reads private key file when present.
/// Caller must free returned slice when `owned` is true.
pub fn resolve(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: anytype,
) !struct { key: ?[]const u8, owned: bool } {
    if (environ.get("GOOGLE_API_KEY")) |k| return .{ .key = k, .owned = false };
    if (environ.get("GEMINI_API_KEY")) |k| return .{ .key = k, .owned = false };
    const path = environ.get("STRIP_GOOGLE_KEY_FILE") orelse default_key_path;
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return .{ .key = null, .owned = false };
    defer file.close(io);
    var buf: [512]u8 = undefined;
    var reader = file.reader(io, &buf);
    const data = reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return .{ .key = null, .owned = false },
        else => return err,
    };
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    if (trimmed.len == 0) return .{ .key = null, .owned = false };
    return .{ .key = try allocator.dupe(u8, trimmed), .owned = true };
}
