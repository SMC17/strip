//! Deterministic Monte Carlo uncertainty propagation and calibration checks.

const std = @import("std");
const distribution = @import("distribution.zig");
const propagate = @import("propagate.zig");
const random = @import("../random/mod.zig");

pub const SampleResult = struct {
    mean: f64,
    variance: f64,
    minimum: f64,
    maximum: f64,
    count: u64,
};

fn gaussianSample(rng: random.CounterRng, trial: u64, channel: usize) f64 {
    const salt = @as(u64, @intCast(channel)) *% 0x9e3779b97f4a7c15;
    const uniform_a = @max(rng.unitF64At(trial *% 2 +% salt), 1.0e-12);
    const uniform_b = rng.unitF64At(trial *% 2 +% salt +% 1);
    return @sqrt(-2.0 * @log(uniform_a)) * @cos(2.0 * std.math.pi * uniform_b);
}

pub fn affineMonteCarlo(
    sensitivities: []const f64,
    means: []const f64,
    standard_deviations: []const f64,
    offset: f64,
    seed: u64,
    trials: u64,
) error{InvalidInput}!SampleResult {
    if (sensitivities.len == 0 or sensitivities.len != means.len or sensitivities.len != standard_deviations.len)
        return error.InvalidInput;
    if (trials == 0 or trials > 1_000_000) return error.InvalidInput;
    var deterministic = offset;
    for (sensitivities, means) |gain, mean| {
        if (!std.math.isFinite(gain) or !std.math.isFinite(mean)) return error.InvalidInput;
        deterministic += gain * mean;
    }
    const rng = random.CounterRng.init(seed, "uncertainty-mc");
    var aggregate: SampleResult = .{
        .mean = 0,
        .variance = 0,
        .minimum = std.math.inf(f64),
        .maximum = -std.math.inf(f64),
        .count = 0,
    };
    var m2: f64 = 0;
    for (0..trials) |index| {
        var value = deterministic;
        for (sensitivities, standard_deviations, 0..) |gain, sigma, channel| {
            if (!std.math.isFinite(sigma) or sigma < 0) return error.InvalidInput;
            const z = gaussianSample(rng, index, channel);
            value += gain * sigma * z;
        }
        aggregate.count += 1;
        aggregate.minimum = @min(aggregate.minimum, value);
        aggregate.maximum = @max(aggregate.maximum, value);
        const delta = value - aggregate.mean;
        aggregate.mean += delta / @as(f64, @floatFromInt(aggregate.count));
        m2 += delta * (value - aggregate.mean);
    }
    if (aggregate.count >= 2) aggregate.variance = m2 / @as(f64, @floatFromInt(aggregate.count - 1));
    return aggregate;
}

pub fn calibratedAgainstAnalytic(
    mc: SampleResult,
    analytic: propagate.Propagated,
    sigma_tolerance: f64,
) error{InvalidCalibration}!bool {
    analytic.validate() catch return error.InvalidCalibration;
    if (!std.math.isFinite(sigma_tolerance) or sigma_tolerance <= 0) return error.InvalidCalibration;
    const analytic_sigma = analytic.uncertainty.value orelse return error.InvalidCalibration;
    const mc_sigma = @sqrt(mc.variance);
    return @abs(mc_sigma - analytic_sigma) <= sigma_tolerance;
}

test "monte carlo affine mean matches analytic propagation" {
    const x = try propagate.fromGaussian(1.0, .{ .mean = 1.0, .variance = 0.01 });
    const y = try propagate.fromGaussian(2.0, .{ .mean = 2.0, .variance = 0.04 });
    const analytic = try propagate.composeAffine(&.{ 3.0, -0.5 }, &.{ x, y }, 1.0);
    const mc = try affineMonteCarlo(&.{ 3.0, -0.5 }, &.{ 1.0, 2.0 }, &.{ 0.1, 0.2 }, 1.0, 42, 100_000);
    try std.testing.expectApproxEqAbs(analytic.value, mc.mean, 0.02);
    const mc_sigma = @sqrt(mc.variance);
    const analytic_sigma = analytic.uncertainty.value.?;
    try std.testing.expectApproxEqRel(analytic_sigma, mc_sigma, 0.15);
}
