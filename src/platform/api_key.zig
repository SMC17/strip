//! Resolve platform API keys from env or private workstation files (never git).

const std = @import("std");

pub const google_default_path = "/home/stax/.local/state/stax/google-api-key";
pub const openrouter_default_path = "/home/stax/.config/openrouter/key";
pub const openrouter_alt_path = "/home/stax/.local/state/stax/openrouter-api-key";

fn readKeyFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);
    var buf: [512]u8 = undefined;
    var reader = file.reader(io, &buf);
    const data = reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}

/// Google / Gemini key.
pub fn resolve(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: anytype,
) !struct { key: ?[]const u8, owned: bool } {
    if (environ.get("GOOGLE_API_KEY")) |k| return .{ .key = k, .owned = false };
    if (environ.get("GEMINI_API_KEY")) |k| return .{ .key = k, .owned = false };
    const path = environ.get("STRIP_GOOGLE_KEY_FILE") orelse google_default_path;
    if (try readKeyFile(io, allocator, path)) |k| return .{ .key = k, .owned = true };
    return .{ .key = null, .owned = false };
}

/// OpenRouter key (platform plane only).
pub fn resolveOpenRouter(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: anytype,
) !struct { key: ?[]const u8, owned: bool } {
    if (environ.get("OPENROUTER_API_KEY")) |k| return .{ .key = k, .owned = false };
    const path = environ.get("STRIP_OPENROUTER_KEY_FILE") orelse openrouter_default_path;
    if (try readKeyFile(io, allocator, path)) |k| return .{ .key = k, .owned = true };
    if (try readKeyFile(io, allocator, openrouter_alt_path)) |k| return .{ .key = k, .owned = true };
    return .{ .key = null, .owned = false };
}
