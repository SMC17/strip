//! Residual diagnostics and uncertainty-normalized empirical coverage.
const std = @import("std");
const telemetry = @import("telemetry.zig");

pub const ResidualSample = struct {
    observed: ?f64,
    predicted: f64,
    combined_standard_uncertainty: ?f64,
    quality: telemetry.Quality,
};

pub const Metrics = struct {
    count: usize,
    omitted: usize,
    mean: f64,
    rms: f64,
    standard_deviation: f64,
    maximum_absolute: f64,
    lag_one_autocorrelation: f64,
    durbin_watson: f64,
    approximate_white: bool,
};

pub const Coverage = struct {
    count: usize,
    omitted: usize,
    within_one_sigma: f64,
    within_two_sigma: f64,
    within_three_sigma: f64,
};

fn usable(sample: ResidualSample) bool {
    return (sample.quality == .valid or sample.quality == .degraded) and
        sample.observed != null;
}

pub fn metrics(samples: []const ResidualSample) !Metrics {
    if (samples.len < 2 or samples.len > 1_000_000) return error.InvalidSampleCount;
    var count: usize = 0;
    var sum: f64 = 0.0;
    var sum_squared: f64 = 0.0;
    var maximum: f64 = 0.0;
    for (samples) |sample| {
        if (!usable(sample)) continue;
        const residual = sample.observed.? - sample.predicted;
        if (!std.math.isFinite(residual)) return error.NonFiniteResidual;
        count += 1;
        sum += residual;
        sum_squared += residual * residual;
        maximum = @max(maximum, @abs(residual));
    }
    if (count < 2) return error.InsufficientUsableSamples;
    const n: f64 = @floatFromInt(count);
    const mean = sum / n;
    var centered_squared: f64 = 0.0;
    var lag_product: f64 = 0.0;
    var difference_squared: f64 = 0.0;
    var previous: ?f64 = null;
    for (samples) |sample| {
        if (!usable(sample)) continue;
        const centered = sample.observed.? - sample.predicted - mean;
        centered_squared += centered * centered;
        if (previous) |prior| {
            lag_product += centered * prior;
            const difference = centered - prior;
            difference_squared += difference * difference;
        }
        previous = centered;
    }
    const autocorrelation = if (centered_squared > 0.0)
        lag_product / centered_squared
    else
        0.0;
    const durbin_watson = if (centered_squared > 0.0)
        difference_squared / centered_squared
    else
        0.0;
    const white_limit = 1.96 / @sqrt(n);
    return .{
        .count = count,
        .omitted = samples.len - count,
        .mean = mean,
        .rms = @sqrt(sum_squared / n),
        .standard_deviation = @sqrt(centered_squared / @as(f64, @floatFromInt(count - 1))),
        .maximum_absolute = maximum,
        .lag_one_autocorrelation = autocorrelation,
        .durbin_watson = durbin_watson,
        .approximate_white = @abs(autocorrelation) <= white_limit,
    };
}

pub fn normalizedCoverage(samples: []const ResidualSample) !Coverage {
    if (samples.len == 0 or samples.len > 1_000_000) return error.InvalidSampleCount;
    var count: usize = 0;
    var within = [3]usize{ 0, 0, 0 };
    for (samples) |sample| {
        if (!usable(sample)) continue;
        const uncertainty = sample.combined_standard_uncertainty orelse continue;
        if (!std.math.isFinite(uncertainty) or uncertainty <= 0.0)
            return error.InvalidUncertainty;
        const normalized = @abs(sample.observed.? - sample.predicted) / uncertainty;
        if (!std.math.isFinite(normalized)) return error.NonFiniteResidual;
        count += 1;
        if (normalized <= 1.0) within[0] += 1;
        if (normalized <= 2.0) within[1] += 1;
        if (normalized <= 3.0) within[2] += 1;
    }
    if (count == 0) return error.NoNormalizedResiduals;
    const n: f64 = @floatFromInt(count);
    return .{
        .count = count,
        .omitted = samples.len - count,
        .within_one_sigma = @as(f64, @floatFromInt(within[0])) / n,
        .within_two_sigma = @as(f64, @floatFromInt(within[1])) / n,
        .within_three_sigma = @as(f64, @floatFromInt(within[2])) / n,
    };
}

test "residual metrics omit missing data and expose serial correlation" {
    const samples = [_]ResidualSample{
        .{ .observed = 1.0, .predicted = 0.0, .combined_standard_uncertainty = 1.0, .quality = .valid },
        .{ .observed = -1.0, .predicted = 0.0, .combined_standard_uncertainty = 1.0, .quality = .valid },
        .{ .observed = 1.0, .predicted = 0.0, .combined_standard_uncertainty = 0.5, .quality = .valid },
        .{ .observed = -1.0, .predicted = 0.0, .combined_standard_uncertainty = 0.25, .quality = .valid },
        .{ .observed = null, .predicted = 0.0, .combined_standard_uncertainty = null, .quality = .missing },
    };
    const result = try metrics(&samples);
    try std.testing.expectEqual(@as(usize, 4), result.count);
    try std.testing.expectEqual(@as(usize, 1), result.omitted);
    try std.testing.expect(result.lag_one_autocorrelation < 0.0);
    const coverage = try normalizedCoverage(&samples);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), coverage.within_one_sigma, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), coverage.within_two_sigma, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), coverage.within_three_sigma, 1.0e-12);
}
