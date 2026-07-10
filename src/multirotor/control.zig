//! Small stateless controller contracts. Gains and limits are explicit caller inputs.

const std = @import("std");
const math = @import("math.zig");

pub const RateController = struct {
    kp_nm_per_radps: math.Vec3,
    maximum_moment_nm: math.Vec3,

    pub fn command(self: RateController, desired_radps: math.Vec3, measured_radps: math.Vec3) math.Vec3 {
        const error_value = desired_radps.sub(measured_radps);
        return .{
            .x = boundedGain(error_value.x, self.kp_nm_per_radps.x, self.maximum_moment_nm.x),
            .y = boundedGain(error_value.y, self.kp_nm_per_radps.y, self.maximum_moment_nm.y),
            .z = boundedGain(error_value.z, self.kp_nm_per_radps.z, self.maximum_moment_nm.z),
        };
    }
};

pub const AttitudeController = struct {
    kp_radps_per_error: math.Vec3,
    maximum_rate_radps: math.Vec3,

    /// Quaternion contract: both arguments are body-to-world active rotations.
    pub fn command(self: AttitudeController, desired_raw: math.Quaternion, measured_raw: math.Quaternion) math.Vec3 {
        const desired = desired_raw.normalized() catch return math.Vec3.zero;
        const measured = measured_raw.normalized() catch return math.Vec3.zero;
        const measured_conjugate = math.Quaternion{
            .w = measured.w,
            .x = -measured.x,
            .y = -measured.y,
            .z = -measured.z,
        };
        var error_q = desired.multiply(measured_conjugate);
        if (error_q.w < 0.0) error_q = error_q.scale(-1.0);
        // Twice the vector part is the bounded small-angle error and remains continuous near hover.
        return .{
            .x = boundedGain(2.0 * error_q.x, self.kp_radps_per_error.x, self.maximum_rate_radps.x),
            .y = boundedGain(2.0 * error_q.y, self.kp_radps_per_error.y, self.maximum_rate_radps.y),
            .z = boundedGain(2.0 * error_q.z, self.kp_radps_per_error.z, self.maximum_rate_radps.z),
        };
    }
};

pub const PositionController = struct {
    kp_per_s2: math.Vec3,
    kd_per_s: math.Vec3,
    maximum_acceleration_mps2: f64,

    pub fn command(
        self: PositionController,
        desired_position_m: math.Vec3,
        desired_velocity_mps: math.Vec3,
        measured_position_m: math.Vec3,
        measured_velocity_mps: math.Vec3,
    ) math.Vec3 {
        if (!(self.maximum_acceleration_mps2 > 0.0) or !std.math.isFinite(self.maximum_acceleration_mps2))
            return math.Vec3.zero;
        const position_error = desired_position_m.sub(measured_position_m);
        const velocity_error = desired_velocity_mps.sub(measured_velocity_mps);
        const unconstrained = math.Vec3{
            .x = position_error.x * nonnegative(self.kp_per_s2.x) + velocity_error.x * nonnegative(self.kd_per_s.x),
            .y = position_error.y * nonnegative(self.kp_per_s2.y) + velocity_error.y * nonnegative(self.kd_per_s.y),
            .z = position_error.z * nonnegative(self.kp_per_s2.z) + velocity_error.z * nonnegative(self.kd_per_s.z),
        };
        const norm = @sqrt(unconstrained.normSquared());
        if (norm <= self.maximum_acceleration_mps2) return unconstrained;
        return unconstrained.scale(self.maximum_acceleration_mps2 / norm);
    }
};

pub const Cascade = struct {
    position: PositionController,
    attitude: AttitudeController,
    rate: RateController,

    pub const Output = struct {
        desired_acceleration_world_mps2: math.Vec3,
        desired_rate_body_radps: math.Vec3,
        desired_moment_body_nm: math.Vec3,
    };

    pub fn command(
        self: Cascade,
        desired_position_m: math.Vec3,
        desired_velocity_mps: math.Vec3,
        desired_attitude: math.Quaternion,
        measured_position_m: math.Vec3,
        measured_velocity_mps: math.Vec3,
        measured_attitude: math.Quaternion,
        measured_rate_body_radps: math.Vec3,
    ) Output {
        const acceleration = self.position.command(
            desired_position_m,
            desired_velocity_mps,
            measured_position_m,
            measured_velocity_mps,
        );
        const rate = self.attitude.command(desired_attitude, measured_attitude);
        return .{
            .desired_acceleration_world_mps2 = acceleration,
            .desired_rate_body_radps = rate,
            .desired_moment_body_nm = self.rate.command(rate, measured_rate_body_radps),
        };
    }
};

fn nonnegative(value: f64) f64 {
    if (!std.math.isFinite(value)) return 0.0;
    return @max(0.0, value);
}

fn boundedGain(error_value: f64, gain: f64, limit: f64) f64 {
    if (!std.math.isFinite(error_value) or !std.math.isFinite(gain) or
        !std.math.isFinite(limit) or gain < 0.0 or limit < 0.0)
        return 0.0;
    return std.math.clamp(gain * error_value, -limit, limit);
}

test "controller contracts preserve signs and enforce limits" {
    const rate = RateController{
        .kp_nm_per_radps = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
        .maximum_moment_nm = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
    };
    const moment = rate.command(.{ .x = 2.0, .y = -0.25, .z = 0.0 }, math.Vec3.zero);
    try std.testing.expectEqual(@as(f64, 1.0), moment.x);
    try std.testing.expectEqual(@as(f64, -0.5), moment.y);

    const position = PositionController{
        .kp_per_s2 = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
        .kd_per_s = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .maximum_acceleration_mps2 = 3.0,
    };
    const acceleration = position.command(
        .{ .x = 10.0, .y = 0.0, .z = 0.0 },
        math.Vec3.zero,
        math.Vec3.zero,
        math.Vec3.zero,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), acceleration.x, 1e-14);
}
