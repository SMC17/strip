//! Fuse flight-test telemetry with analytic priors under explicit quality gates.

const std = @import("std");
const propagate = @import("propagate.zig");
const flight_test = @import("../flight_test/telemetry.zig");

pub const Observation = struct {
    value: f64,
    standard_uncertainty: f64,
    quality: flight_test.Quality,
};

pub const FusionReport = struct {
    fused_value: f64,
    fused_standard_uncertainty: f64,
    prior_weight: f64,
    observation_weight: f64,
    observation_used: bool,
};

pub fn fuse(
    prior: propagate.Propagated,
    observation: Observation,
) error{InvalidFusion}!FusionReport {
    prior.validate() catch return error.InvalidFusion;
    if (!std.math.isFinite(observation.value) or !std.math.isFinite(observation.standard_uncertainty) or
        observation.standard_uncertainty <= 0.0)
        return error.InvalidFusion;
    const prior_sigma = prior.uncertainty.value orelse return error.InvalidFusion;
    if (!observationUsable(observation)) {
        return .{
            .fused_value = prior.value,
            .fused_standard_uncertainty = prior_sigma,
            .prior_weight = 1.0,
            .observation_weight = 0.0,
            .observation_used = false,
        };
    }
    const prior_variance = prior_sigma * prior_sigma;
    const observation_variance = observation.standard_uncertainty * observation.standard_uncertainty;
    const prior_weight = 1.0 / prior_variance;
    const observation_weight = 1.0 / observation_variance;
    const total = prior_weight + observation_weight;
    const fused_value = (prior_weight * prior.value + observation_weight * observation.value) / total;
    const fused_variance = 1.0 / total;
    return .{
        .fused_value = fused_value,
        .fused_standard_uncertainty = @sqrt(fused_variance),
        .prior_weight = prior_weight / total,
        .observation_weight = observation_weight / total,
        .observation_used = true,
    };
}

fn observationUsable(observation: Observation) bool {
    return observation.quality == .valid or observation.quality == .degraded;
}

test "fusion ignores missing observations and tightens with valid data" {
    const prior = try propagate.fromGaussian(0.0, .{ .mean = 0.0, .variance = 1.0 });
    const missing = try fuse(prior, .{ .value = 10.0, .standard_uncertainty = 0.1, .quality = .missing });
    try std.testing.expect(!missing.observation_used);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), missing.fused_value, 1e-12);

    const fused = try fuse(prior, .{ .value = 1.0, .standard_uncertainty = 0.2, .quality = .valid });
    try std.testing.expect(fused.observation_used);
    try std.testing.expect(fused.fused_standard_uncertainty < 1.0);
    try std.testing.expect(fused.fused_value > 0.0);
}
