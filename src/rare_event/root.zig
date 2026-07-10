//! Weighted rare-event estimate bookkeeping, independent of sampling method.
const std = @import("std");

pub const WeightedOutcome = struct {
    occurred: bool,
    likelihood_ratio: f64,
};

pub fn probabilityEstimate(outcomes: []const WeightedOutcome) error{
    EmptySample,
    InvalidWeight,
}!f64 {
    if (outcomes.len == 0) return error.EmptySample;
    var weighted_events: f64 = 0;
    for (outcomes) |outcome| {
        if (!std.math.isFinite(outcome.likelihood_ratio) or outcome.likelihood_ratio < 0)
            return error.InvalidWeight;
        if (outcome.occurred) weighted_events += outcome.likelihood_ratio;
    }
    return weighted_events / @as(f64, @floatFromInt(outcomes.len));
}

test "estimator uses explicit likelihood ratios" {
    const estimate = try probabilityEstimate(&.{
        .{ .occurred = true, .likelihood_ratio = 0.01 },
        .{ .occurred = false, .likelihood_ratio = 0.5 },
    });
    try std.testing.expectApproxEqAbs(@as(f64, 0.005), estimate, 1e-12);
    try std.testing.expectError(
        error.InvalidWeight,
        probabilityEstimate(&.{.{ .occurred = true, .likelihood_ratio = -1 }}),
    );
}
