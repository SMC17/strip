//! Finite-difference consistency checks for position, velocity, and acceleration.
const std = @import("std");
const calibration = @import("calibration.zig");

pub const StateSample = struct {
    time_s: f64,
    position_m: calibration.Vec3,
    velocity_mps: calibration.Vec3,
    acceleration_mps2: calibration.Vec3,
};

pub const Consistency = struct {
    position_velocity_rms: f64,
    velocity_acceleration_rms: f64,
    maximum_component_error: f64,
    intervals: usize,

    pub fn passes(self: Consistency, rms_limit: f64, component_limit: f64) bool {
        return std.math.isFinite(rms_limit) and rms_limit >= 0.0 and
            std.math.isFinite(component_limit) and component_limit >= 0.0 and
            self.position_velocity_rms <= rms_limit and
            self.velocity_acceleration_rms <= rms_limit and
            self.maximum_component_error <= component_limit;
    }
};

pub fn check(samples: []const StateSample) !Consistency {
    if (samples.len < 2 or samples.len > 1_000_000) return error.InvalidSampleCount;
    var pv_squared: f64 = 0.0;
    var va_squared: f64 = 0.0;
    var maximum: f64 = 0.0;
    for (samples[0 .. samples.len - 1], samples[1..]) |left, right| {
        const dt = right.time_s - left.time_s;
        if (!std.math.isFinite(dt) or dt <= 0.0) return error.NonMonotonicTime;
        for (0..3) |axis| {
            const velocity_from_position =
                (right.position_m[axis] - left.position_m[axis]) / dt;
            const acceleration_from_velocity =
                (right.velocity_mps[axis] - left.velocity_mps[axis]) / dt;
            const midpoint_velocity = 0.5 * (left.velocity_mps[axis] + right.velocity_mps[axis]);
            const midpoint_acceleration =
                0.5 * (left.acceleration_mps2[axis] + right.acceleration_mps2[axis]);
            const pv_error = velocity_from_position - midpoint_velocity;
            const va_error = acceleration_from_velocity - midpoint_acceleration;
            if (!std.math.isFinite(pv_error) or !std.math.isFinite(va_error))
                return error.NonFiniteState;
            pv_squared += pv_error * pv_error;
            va_squared += va_error * va_error;
            maximum = @max(maximum, @max(@abs(pv_error), @abs(va_error)));
        }
    }
    const components: f64 = @floatFromInt((samples.len - 1) * 3);
    return .{
        .position_velocity_rms = @sqrt(pv_squared / components),
        .velocity_acceleration_rms = @sqrt(va_squared / components),
        .maximum_component_error = maximum,
        .intervals = samples.len - 1,
    };
}

test "kinematic check accepts constant acceleration trajectory" {
    const samples = [_]StateSample{
        .{ .time_s = 0.0, .position_m = .{ 0, 0, 0 }, .velocity_mps = .{ 0, 0, 0 }, .acceleration_mps2 = .{ 2, 0, 0 } },
        .{ .time_s = 1.0, .position_m = .{ 1, 0, 0 }, .velocity_mps = .{ 2, 0, 0 }, .acceleration_mps2 = .{ 2, 0, 0 } },
        .{ .time_s = 2.0, .position_m = .{ 4, 0, 0 }, .velocity_mps = .{ 4, 0, 0 }, .acceleration_mps2 = .{ 2, 0, 0 } },
    };
    const result = try check(&samples);
    try std.testing.expect(result.passes(1.0e-12, 1.0e-12));
}
