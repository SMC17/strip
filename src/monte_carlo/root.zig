//! Allocation-free aggregation for repeated deterministic trials.
const std = @import("std");

pub const Aggregate = struct {
    count: u64 = 0,
    failures: u64 = 0,
    mean: f64 = 0,
    m2: f64 = 0,
    minimum: f64 = std.math.inf(f64),
    maximum: f64 = -std.math.inf(f64),

    pub fn add(self: *Aggregate, value: f64, failed: bool) error{NonFiniteSample}!void {
        if (!std.math.isFinite(value)) return error.NonFiniteSample;
        self.count += 1;
        if (failed) self.failures += 1;
        self.minimum = @min(self.minimum, value);
        self.maximum = @max(self.maximum, value);
        const delta = value - self.mean;
        self.mean += delta / @as(f64, @floatFromInt(self.count));
        self.m2 += delta * (value - self.mean);
    }

    pub fn sampleVariance(self: Aggregate) ?f64 {
        if (self.count < 2) return null;
        return self.m2 / @as(f64, @floatFromInt(self.count - 1));
    }

    pub fn failureRate(self: Aggregate) ?f64 {
        if (self.count == 0) return null;
        return @as(f64, @floatFromInt(self.failures)) /
            @as(f64, @floatFromInt(self.count));
    }
};

pub const TrialResult = struct {
    seed: u64,
    metric: f64,
    failed: bool,
};

pub fn aggregate(trials: []const TrialResult) error{NonFiniteSample}!Aggregate {
    var result: Aggregate = .{};
    for (trials) |trial| try result.add(trial.metric, trial.failed);
    return result;
}

test "online aggregate reports stable moments and failure rate" {
    const result = try aggregate(&.{
        .{ .seed = 1, .metric = 1, .failed = false },
        .{ .seed = 2, .metric = 2, .failed = true },
        .{ .seed = 3, .metric = 3, .failed = false },
    });
    try std.testing.expectEqual(@as(u64, 3), result.count);
    try std.testing.expectApproxEqAbs(@as(f64, 2), result.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1), result.sampleVariance().?, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), result.failureRate().?, 1e-12);
}

test "non-finite samples are refused without changing aggregate" {
    var result: Aggregate = .{};
    try std.testing.expectError(error.NonFiniteSample, result.add(std.math.nan(f64), false));
    try std.testing.expectEqual(@as(u64, 0), result.count);
}
