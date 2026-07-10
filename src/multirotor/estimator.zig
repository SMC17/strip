//! Deterministic estimator building blocks, not a navigation solution.

const std = @import("std");
const math = @import("math.zig");

pub const AttitudePropagator = struct {
    body_to_world: math.Quaternion = math.Quaternion.identity,

    /// First-order gyro propagation followed by mandatory unit normalization.
    pub fn step(self: *AttitudePropagator, angular_velocity_body_radps: math.Vec3, dt_s: f64) error{InvalidStep}!math.Quaternion {
        if (!angular_velocity_body_radps.isFinite() or !(dt_s > 0.0) or !std.math.isFinite(dt_s))
            return error.InvalidStep;
        const derivative = self.body_to_world.derivativeBodyRate(angular_velocity_body_radps);
        self.body_to_world = self.body_to_world.add(derivative.scale(dt_s)).normalized() catch
            return error.InvalidStep;
        return self.body_to_world;
    }
};

pub const ScalarComplementary = struct {
    estimate: f64,
    velocity: f64,
    correction_gain_per_s: f64,

    /// Predicts with acceleration, then applies a bounded position correction.
    pub fn step(
        self: *ScalarComplementary,
        acceleration: f64,
        position_measurement: ?f64,
        maximum_correction: f64,
        dt_s: f64,
    ) error{InvalidStep}!f64 {
        if (!std.math.isFinite(acceleration) or !std.math.isFinite(maximum_correction) or
            maximum_correction < 0.0 or !std.math.isFinite(self.correction_gain_per_s) or
            self.correction_gain_per_s < 0.0 or !(dt_s > 0.0) or !std.math.isFinite(dt_s))
            return error.InvalidStep;
        self.estimate += self.velocity * dt_s + 0.5 * acceleration * dt_s * dt_s;
        self.velocity += acceleration * dt_s;
        if (position_measurement) |measurement| {
            if (!std.math.isFinite(measurement)) return error.InvalidStep;
            const correction = std.math.clamp(
                self.correction_gain_per_s * (measurement - self.estimate) * dt_s,
                -maximum_correction,
                maximum_correction,
            );
            self.estimate += correction;
        }
        return self.estimate;
    }
};

test "attitude propagation remains normalized and deterministic" {
    var first = AttitudePropagator{};
    var second = AttitudePropagator{};
    for (0..100) |_| {
        const a = try first.step(.{ .x = 0.1, .y = -0.2, .z = 0.3 }, 0.01);
        const b = try second.step(.{ .x = 0.1, .y = -0.2, .z = 0.3 }, 0.01);
        try std.testing.expectEqualDeep(a, b);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), first.body_to_world.normSquared(), 1e-12);
}

test "scalar correction is bounded" {
    var estimator = ScalarComplementary{ .estimate = 0.0, .velocity = 0.0, .correction_gain_per_s = 10.0 };
    try std.testing.expectEqual(@as(f64, 0.5), try estimator.step(0.0, 100.0, 0.5, 1.0));
}
