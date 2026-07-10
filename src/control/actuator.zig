//! Bounded first-order actuator with position and slew-rate limits.

const std = @import("std");

pub const Config = struct {
    minimum: f64,
    maximum: f64,
    max_rate_per_s: f64,
    time_constant_s: f64,

    pub fn validate(self: Config) error{InvalidConfiguration}!void {
        if (!std.math.isFinite(self.minimum) or !std.math.isFinite(self.maximum) or
            !std.math.isFinite(self.max_rate_per_s) or !std.math.isFinite(self.time_constant_s) or
            !(self.maximum > self.minimum) or !(self.max_rate_per_s > 0.0) or !(self.time_constant_s > 0.0))
        {
            return error.InvalidConfiguration;
        }
    }
};

pub const Actuator = struct {
    config: Config,
    position: f64,

    pub fn init(config: Config, initial_position: f64) error{ InvalidConfiguration, InitialPositionOutsideLimits }!Actuator {
        try config.validate();
        if (!std.math.isFinite(initial_position) or initial_position < config.minimum or initial_position > config.maximum) {
            return error.InitialPositionOutsideLimits;
        }
        return .{ .config = config, .position = initial_position };
    }

    pub fn step(self: *Actuator, command_raw: f64, dt_s: f64) error{InvalidStep}!f64 {
        if (!(dt_s > 0.0) or !std.math.isFinite(dt_s) or !std.math.isFinite(command_raw)) {
            return error.InvalidStep;
        }
        const command = std.math.clamp(command_raw, self.config.minimum, self.config.maximum);
        const unconstrained_rate = (command - self.position) / self.config.time_constant_s;
        const rate = std.math.clamp(
            unconstrained_rate,
            -self.config.max_rate_per_s,
            self.config.max_rate_per_s,
        );
        self.position = std.math.clamp(
            self.position + rate * dt_s,
            self.config.minimum,
            self.config.maximum,
        );
        return self.position;
    }
};

test "actuator obeys slew and position limits" {
    var actuator = try Actuator.init(.{
        .minimum = -1.0,
        .maximum = 1.0,
        .max_rate_per_s = 0.5,
        .time_constant_s = 0.2,
    }, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.05), try actuator.step(2.0, 0.1), 1e-14);
    for (0..100) |_| _ = try actuator.step(2.0, 0.1);
    try std.testing.expectEqual(@as(f64, 1.0), actuator.position);
}
