//! Fixed-step PID with derivative-on-measurement and conditional anti-windup.

const std = @import("std");
const evidence = @import("../evidence.zig");
const numerical_result = @import("../result.zig");

pub const manifest = evidence.ModelManifest{
    .id = "strip.control.pid",
    .version = "0.1.0",
    .proof_level = .unit_tested,
    .source = "Fixed-step PID with derivative-on-measurement",
    .assumptions = &.{
        "fixed sample period",
        "conditional anti-windup",
    },
    .valid_min = 1e-6,
    .valid_max = 10.0,
    .valid_unit = "s",
    .proof = .{
        .implementation = .implemented,
        .testing = .unit_tested,
        .analysis = .none,
        .comparison = .none,
        .validation = .none,
    },
};

pub const Config = struct {
    kp: f64,
    ki: f64,
    kd: f64,
    output_min: f64,
    output_max: f64,
    integral_min: f64,
    integral_max: f64,

    pub fn validate(self: Config) error{InvalidConfiguration}!void {
        const values = [_]f64{
            self.kp,           self.ki,         self.kd,
            self.output_min,   self.output_max, self.integral_min,
            self.integral_max,
        };
        for (values) |value| if (!std.math.isFinite(value)) return error.InvalidConfiguration;
        if (self.kp < 0.0 or self.ki < 0.0 or self.kd < 0.0 or
            !(self.output_max > self.output_min) or !(self.integral_max >= self.integral_min))
        {
            return error.InvalidConfiguration;
        }
    }
};

pub const Pid = struct {
    config: Config,
    integral: f64 = 0.0,
    previous_measurement: ?f64 = null,

    pub fn init(config: Config) error{InvalidConfiguration}!Pid {
        try config.validate();
        return .{ .config = config };
    }

    pub fn reset(self: *Pid) void {
        self.integral = 0.0;
        self.previous_measurement = null;
    }

    pub fn step(self: *Pid, setpoint: f64, measurement: f64, dt_s: f64) error{InvalidStep}!f64 {
        if (!(dt_s > 0.0) or !std.math.isFinite(dt_s) or
            !std.math.isFinite(setpoint) or !std.math.isFinite(measurement))
        {
            return error.InvalidStep;
        }

        const error_value = setpoint - measurement;
        const derivative_measurement = if (self.previous_measurement) |previous|
            (measurement - previous) / dt_s
        else
            0.0;
        self.previous_measurement = measurement;

        const candidate_integral = std.math.clamp(
            self.integral + error_value * dt_s,
            self.config.integral_min,
            self.config.integral_max,
        );
        const candidate_output = self.config.kp * error_value +
            self.config.ki * candidate_integral -
            self.config.kd * derivative_measurement;

        const drives_high_saturation = candidate_output > self.config.output_max and error_value > 0.0;
        const drives_low_saturation = candidate_output < self.config.output_min and error_value < 0.0;
        if (!drives_high_saturation and !drives_low_saturation) self.integral = candidate_integral;

        const output = self.config.kp * error_value +
            self.config.ki * self.integral -
            self.config.kd * derivative_measurement;
        return std.math.clamp(output, self.config.output_min, self.config.output_max);
    }

    pub fn stepResult(
        self: *Pid,
        context: evidence.Context,
        setpoint: f64,
        measurement: f64,
        dt_s: f64,
    ) error{InvalidStep}!numerical_result.NumericalResult(?f64) {
        const envelope = manifest.effectiveEnvelope("dt_s");
        if (!envelope.contains(dt_s)) {
            return .{
                .value = null,
                .model = manifest,
                .context = context,
                .validity = .outside_envelope,
                .evaluated_point = .{ .variable = "dt_s", .value = dt_s, .unit = "s" },
                .envelope = envelope,
                .execution_identity = .fromModel(manifest),
                .credibility = .fromProof(manifest.effectiveProof()),
            };
        }
        const output = try self.step(setpoint, measurement, dt_s);
        return .{
            .value = output,
            .model = manifest,
            .context = context,
            .validity = .valid,
            .evaluated_point = .{ .variable = "dt_s", .value = dt_s, .unit = "s" },
            .envelope = envelope,
            .execution_identity = .fromModel(manifest),
            .credibility = .fromProof(manifest.effectiveProof()),
        };
    }
};

test "PID output clamps without integrating farther into saturation" {
    var pid = try Pid.init(.{
        .kp = 2.0,
        .ki = 1.0,
        .kd = 0.0,
        .output_min = -1.0,
        .output_max = 1.0,
        .integral_min = -10.0,
        .integral_max = 10.0,
    });
    for (0..20) |_| try std.testing.expectEqual(@as(f64, 1.0), try pid.step(10.0, 0.0, 0.1));
    try std.testing.expectEqual(@as(f64, 0.0), pid.integral);
}

test "derivative-on-measurement avoids setpoint kick" {
    var pid = try Pid.init(.{
        .kp = 0.0,
        .ki = 0.0,
        .kd = 1.0,
        .output_min = -100.0,
        .output_max = 100.0,
        .integral_min = 0.0,
        .integral_max = 0.0,
    });
    _ = try pid.step(0.0, 2.0, 0.1);
    try std.testing.expectEqual(@as(f64, 0.0), try pid.step(10.0, 2.0, 0.1));
    try std.testing.expectApproxEqAbs(@as(f64, -10.0), try pid.step(10.0, 3.0, 0.1), 1e-14);
}
