//! Deterministic, discrete IMU error model: fixed bias, independent Gaussian
//! white noise, quantization, and symmetric saturation. No vibration, scale
//! factor, axis misalignment, bias walk, or temperature dependence is modeled.

const std = @import("std");
const math = @import("../dynamics/math.zig");
const noise = @import("noise.zig");

pub const Config = struct {
    accelerometer_bias_mps2: math.Vec3 = math.Vec3.zero,
    gyroscope_bias_radps: math.Vec3 = math.Vec3.zero,
    accelerometer_noise_std_mps2: f64 = 0.0,
    gyroscope_noise_std_radps: f64 = 0.0,
    accelerometer_quantization_mps2: f64 = 0.0,
    gyroscope_quantization_radps: f64 = 0.0,
    accelerometer_range_mps2: f64,
    gyroscope_range_radps: f64,

    pub fn validate(self: Config) error{InvalidConfiguration}!void {
        if (!self.accelerometer_bias_mps2.isFinite() or !self.gyroscope_bias_radps.isFinite()) {
            return error.InvalidConfiguration;
        }
        const values = [_]f64{
            self.accelerometer_noise_std_mps2,
            self.gyroscope_noise_std_radps,
            self.accelerometer_quantization_mps2,
            self.gyroscope_quantization_radps,
            self.accelerometer_range_mps2,
            self.gyroscope_range_radps,
        };
        for (values) |value| if (!std.math.isFinite(value)) return error.InvalidConfiguration;
        if (self.accelerometer_noise_std_mps2 < 0.0 or self.gyroscope_noise_std_radps < 0.0 or
            self.accelerometer_quantization_mps2 < 0.0 or self.gyroscope_quantization_radps < 0.0 or
            !(self.accelerometer_range_mps2 > 0.0) or !(self.gyroscope_range_radps > 0.0))
        {
            return error.InvalidConfiguration;
        }
    }
};

pub const Sample = struct {
    specific_force_body_mps2: math.Vec3,
    angular_velocity_body_radps: math.Vec3,
};

pub const Imu = struct {
    config: Config,
    generator: noise.Generator,

    pub fn init(config: Config, seed: u64) error{InvalidConfiguration}!Imu {
        try config.validate();
        return .{ .config = config, .generator = noise.Generator.init(seed) };
    }

    fn axis(
        generator: *noise.Generator,
        truth: f64,
        bias: f64,
        noise_std: f64,
        quantum: f64,
        range: f64,
    ) f64 {
        var value = truth + bias + generator.normal(noise_std);
        if (quantum > 0.0) value = @round(value / quantum) * quantum;
        return std.math.clamp(value, -range, range);
    }

    fn vector(
        generator: *noise.Generator,
        truth: math.Vec3,
        bias: math.Vec3,
        noise_std: f64,
        quantum: f64,
        range: f64,
    ) math.Vec3 {
        return .{
            .x = axis(generator, truth.x, bias.x, noise_std, quantum, range),
            .y = axis(generator, truth.y, bias.y, noise_std, quantum, range),
            .z = axis(generator, truth.z, bias.z, noise_std, quantum, range),
        };
    }

    pub fn sample(
        self: *Imu,
        true_specific_force_body_mps2: math.Vec3,
        true_angular_velocity_body_radps: math.Vec3,
    ) Sample {
        return .{
            .specific_force_body_mps2 = vector(
                &self.generator,
                true_specific_force_body_mps2,
                self.config.accelerometer_bias_mps2,
                self.config.accelerometer_noise_std_mps2,
                self.config.accelerometer_quantization_mps2,
                self.config.accelerometer_range_mps2,
            ),
            .angular_velocity_body_radps = vector(
                &self.generator,
                true_angular_velocity_body_radps,
                self.config.gyroscope_bias_radps,
                self.config.gyroscope_noise_std_radps,
                self.config.gyroscope_quantization_radps,
                self.config.gyroscope_range_radps,
            ),
        };
    }
};

fn testConfig() Config {
    return .{
        .accelerometer_noise_std_mps2 = 0.01,
        .gyroscope_noise_std_radps = 0.001,
        .accelerometer_range_mps2 = 100.0,
        .gyroscope_range_radps = 20.0,
    };
}

test "same IMU seed produces identical samples" {
    var first = try Imu.init(testConfig(), 1234);
    var second = try Imu.init(testConfig(), 1234);
    for (0..10) |_| {
        try std.testing.expectEqualDeep(
            first.sample(.{ .x = 1.0, .y = 2.0, .z = 3.0 }, .{ .x = 0.1, .y = 0.2, .z = 0.3 }),
            second.sample(.{ .x = 1.0, .y = 2.0, .z = 3.0 }, .{ .x = 0.1, .y = 0.2, .z = 0.3 }),
        );
    }
}

test "ideal IMU passes truth until saturation" {
    var imu = try Imu.init(.{
        .accelerometer_range_mps2 = 10.0,
        .gyroscope_range_radps = 2.0,
    }, 1);
    const measured = imu.sample(.{ .x = 3.0, .y = -4.0, .z = 20.0 }, .{ .x = 0.5, .y = -3.0, .z = 0.0 });
    try std.testing.expectEqualDeep(math.Vec3{ .x = 3.0, .y = -4.0, .z = 10.0 }, measured.specific_force_body_mps2);
    try std.testing.expectEqualDeep(math.Vec3{ .x = 0.5, .y = -2.0, .z = 0.0 }, measured.angular_velocity_body_radps);
}
