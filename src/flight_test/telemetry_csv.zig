//! CSV telemetry loader for bounded flight-test campaign gates.

const std = @import("std");
const telemetry = @import("telemetry.zig");
const cards = @import("cards.zig");

pub const CsvRow = struct {
    sequence: u64,
    time_ns: i128,
    channel: []const u8,
    value: ?f64,
    standard_uncertainty: ?f64,
    quality: telemetry.Quality,
    split: cards.Split,
};

pub fn parseSplit(text: []const u8) !cards.Split {
    if (std.mem.eql(u8, text, "calibration")) return .calibration;
    if (std.mem.eql(u8, text, "blinded_holdout")) return .blinded_holdout;
    return error.InvalidSplit;
}

pub fn parseQuality(text: []const u8) !telemetry.Quality {
    if (std.mem.eql(u8, text, "valid")) return .valid;
    if (std.mem.eql(u8, text, "degraded")) return .degraded;
    if (std.mem.eql(u8, text, "invalid")) return .invalid;
    if (std.mem.eql(u8, text, "missing")) return .missing;
    return error.InvalidQuality;
}

pub fn loadCsv(allocator: std.mem.Allocator, bytes: []const u8) ![]CsvRow {
    var rows = try std.ArrayList(CsvRow).initCapacity(allocator, 64);
    errdefer rows.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next(); // header
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        var fields = std.mem.splitScalar(u8, trimmed, ',');
        const sequence_text = fields.next() orelse return error.InvalidCsv;
        const time_text = fields.next() orelse return error.InvalidCsv;
        _ = fields.next(); // utc_ns
        const channel = fields.next() orelse return error.InvalidCsv;
        const value_text = fields.next() orelse return error.InvalidCsv;
        const uncertainty_text = fields.next() orelse return error.InvalidCsv;
        const quality_text = fields.next() orelse return error.InvalidCsv;
        const split_text = fields.next() orelse return error.InvalidCsv;

        const sequence = try std.fmt.parseInt(u64, sequence_text, 10);
        const time_ns = try std.fmt.parseInt(i128, time_text, 10);
        const value: ?f64 = if (value_text.len == 0) null else try std.fmt.parseFloat(f64, value_text);
        const uncertainty: ?f64 = if (uncertainty_text.len == 0) null else try std.fmt.parseFloat(f64, uncertainty_text);
        const quality = try parseQuality(quality_text);
        const split = try parseSplit(split_text);

        const channel_copy = try allocator.dupe(u8, channel);
        try rows.append(allocator, .{
            .sequence = sequence,
            .time_ns = time_ns,
            .channel = channel_copy,
            .value = value,
            .standard_uncertainty = uncertainty,
            .quality = quality,
            .split = split,
        });
    }
    return try rows.toOwnedSlice(allocator);
}

test "synthetic telemetry csv loads with explicit splits" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/validation/flight-test/synthetic-telemetry.csv",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    const rows = try loadCsv(std.testing.allocator, bytes);
    defer {
        for (rows) |row| std.testing.allocator.free(row.channel);
        std.testing.allocator.free(rows);
    }
    try std.testing.expectEqual(@as(usize, 4), rows.len);
    try std.testing.expectEqual(cards.Split.calibration, rows[0].split);
    try std.testing.expectEqual(cards.Split.blinded_holdout, rows[3].split);
}
