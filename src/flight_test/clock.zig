//! Affine reconciliation between monotonic, UTC, and GNSS clock domains.
const std = @import("std");
const telemetry = @import("telemetry.zig");

pub const max_anchors = 4096;

pub const Anchor = struct {
    source_ns: i128,
    reference_ns: i128,
    quality: telemetry.Quality,
};

pub const AffineClock = struct {
    source: telemetry.ClockDomain,
    reference: telemetry.ClockDomain,
    source_origin_ns: i128,
    reference_origin_ns: i128,
    scale: f64,
    rms_error_ns: f64,
    used_anchors: usize,

    pub fn map(self: AffineClock, source_ns: i128) !i128 {
        const delta: f64 = @floatFromInt(source_ns - self.source_origin_ns);
        const mapped_delta = self.scale * delta;
        if (!std.math.isFinite(mapped_delta)) return error.ClockOverflow;
        return self.reference_origin_ns + @as(i128, @intFromFloat(@round(mapped_delta)));
    }

    pub fn driftPpm(self: AffineClock) f64 {
        return (self.scale - 1.0) * 1.0e6;
    }
};

pub fn reconcile(
    source: telemetry.ClockDomain,
    reference: telemetry.ClockDomain,
    anchors: []const Anchor,
) !AffineClock {
    if (source == reference) return error.IdenticalClockDomains;
    if (anchors.len < 2 or anchors.len > max_anchors) return error.InvalidAnchorCount;

    var first: ?Anchor = null;
    for (anchors) |anchor| {
        if (anchor.quality == .valid or anchor.quality == .degraded) {
            first = anchor;
            break;
        }
    }
    const origin = first orelse return error.InsufficientUsableAnchors;

    var sum_x: f64 = 0.0;
    var sum_y: f64 = 0.0;
    var count: usize = 0;
    for (anchors) |anchor| {
        if (anchor.quality != .valid and anchor.quality != .degraded) continue;
        sum_x += @floatFromInt(anchor.source_ns - origin.source_ns);
        sum_y += @floatFromInt(anchor.reference_ns - origin.reference_ns);
        count += 1;
    }
    if (count < 2) return error.InsufficientUsableAnchors;
    const n: f64 = @floatFromInt(count);
    const mean_x = sum_x / n;
    const mean_y = sum_y / n;
    var sxx: f64 = 0.0;
    var sxy: f64 = 0.0;
    for (anchors) |anchor| {
        if (anchor.quality != .valid and anchor.quality != .degraded) continue;
        const x: f64 = @floatFromInt(anchor.source_ns - origin.source_ns);
        const y: f64 = @floatFromInt(anchor.reference_ns - origin.reference_ns);
        sxx += (x - mean_x) * (x - mean_x);
        sxy += (x - mean_x) * (y - mean_y);
    }
    if (sxx <= 0.0) return error.UnobservableClockScale;
    const scale = sxy / sxx;
    if (!std.math.isFinite(scale) or scale <= 0.0) return error.InvalidClockScale;
    const intercept = mean_y - scale * mean_x;
    var squared_error: f64 = 0.0;
    for (anchors) |anchor| {
        if (anchor.quality != .valid and anchor.quality != .degraded) continue;
        const x: f64 = @floatFromInt(anchor.source_ns - origin.source_ns);
        const y: f64 = @floatFromInt(anchor.reference_ns - origin.reference_ns);
        const residual = y - (intercept + scale * x);
        squared_error += residual * residual;
    }
    return .{
        .source = source,
        .reference = reference,
        .source_origin_ns = origin.source_ns,
        .reference_origin_ns = origin.reference_ns + @as(i128, @intFromFloat(@round(intercept))),
        .scale = scale,
        .rms_error_ns = @sqrt(squared_error / n),
        .used_anchors = count,
    };
}

test "affine clock reconciliation recovers offset and drift" {
    const offset: i128 = 1_700_000_000_000_000_000;
    const anchors = [_]Anchor{
        .{ .source_ns = 0, .reference_ns = offset, .quality = .valid },
        .{ .source_ns = 1_000_000_000, .reference_ns = offset + 1_000_025_000, .quality = .valid },
        .{ .source_ns = 2_000_000_000, .reference_ns = offset + 2_000_050_000, .quality = .valid },
        .{ .source_ns = 3_000_000_000, .reference_ns = offset + 9_000_000_000, .quality = .invalid },
    };
    const fit = try reconcile(.monotonic, .utc, &anchors);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), fit.driftPpm(), 1.0e-6);
    try std.testing.expectEqual(offset + 4_000_100_000, try fit.map(4_000_000_000));
    try std.testing.expectEqual(@as(usize, 3), fit.used_anchors);

    const gnss_utc = [_]Anchor{
        .{ .source_ns = 10_000_000_000, .reference_ns = offset, .quality = .valid },
        .{ .source_ns = 11_000_000_000, .reference_ns = offset + 1_000_000_000, .quality = .valid },
    };
    const gnss_fit = try reconcile(.gnss, .utc, &gnss_utc);
    try std.testing.expectEqual(offset + 2_000_000_000, try gnss_fit.map(12_000_000_000));
}
