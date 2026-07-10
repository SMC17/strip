//! Three-axis bias, scale, and rigid sensor-to-body mount calibration.
const std = @import("std");

pub const Vec3 = [3]f64;
pub const Mat3 = [3][3]f64;

pub const SensorCalibration = struct {
    bias: Vec3,
    scale: Vec3,
    sensor_to_body: Mat3,

    pub fn validate(self: SensorCalibration) !void {
        for (self.bias) |value| if (!std.math.isFinite(value)) return error.NonFiniteCalibration;
        for (self.scale) |value| {
            if (!std.math.isFinite(value) or value == 0.0) return error.InvalidScale;
        }
        for (0..3) |row| {
            var norm: f64 = 0.0;
            for (0..3) |column| {
                const value = self.sensor_to_body[row][column];
                if (!std.math.isFinite(value)) return error.NonFiniteCalibration;
                norm += value * value;
            }
            if (@abs(norm - 1.0) > 1.0e-6) return error.InvalidMountMatrix;
            for (0..row) |prior| {
                var dot: f64 = 0.0;
                for (0..3) |column|
                    dot += self.sensor_to_body[row][column] * self.sensor_to_body[prior][column];
                if (@abs(dot) > 1.0e-6) return error.InvalidMountMatrix;
            }
        }
        const m = self.sensor_to_body;
        const determinant =
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
            m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
            m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
        if (@abs(determinant - 1.0) > 1.0e-6) return error.InvalidMountMatrix;
    }

    pub fn apply(self: SensorCalibration, raw: Vec3) !Vec3 {
        try self.validate();
        var scaled: Vec3 = undefined;
        for (0..3) |axis| {
            if (!std.math.isFinite(raw[axis])) return error.NonFiniteMeasurement;
            scaled[axis] = (raw[axis] - self.bias[axis]) * self.scale[axis];
        }
        var body: Vec3 = .{ 0.0, 0.0, 0.0 };
        for (0..3) |row| {
            for (0..3) |column| {
                body[row] += self.sensor_to_body[row][column] * scaled[column];
            }
        }
        return body;
    }
};

pub fn fitBiasScale(raw: []const Vec3, reference: []const Vec3, mount: Mat3) !SensorCalibration {
    if (raw.len != reference.len) return error.DimensionMismatch;
    if (raw.len < 3 or raw.len > 100_000) return error.InvalidCalibrationCount;
    var calibration: SensorCalibration = .{
        .bias = undefined,
        .scale = undefined,
        .sensor_to_body = mount,
    };
    for (0..3) |axis| {
        var sum_x: f64 = 0.0;
        var sum_y: f64 = 0.0;
        for (raw, reference) |x, y| {
            if (!std.math.isFinite(x[axis]) or !std.math.isFinite(y[axis]))
                return error.NonFiniteMeasurement;
            sum_x += x[axis];
            sum_y += y[axis];
        }
        const n: f64 = @floatFromInt(raw.len);
        const mean_x = sum_x / n;
        const mean_y = sum_y / n;
        var sxx: f64 = 0.0;
        var sxy: f64 = 0.0;
        for (raw, reference) |x, y| {
            sxx += (x[axis] - mean_x) * (x[axis] - mean_x);
            sxy += (x[axis] - mean_x) * (y[axis] - mean_y);
        }
        if (sxx <= 1.0e-18) return error.UnobservableAxis;
        calibration.scale[axis] = sxy / sxx;
        if (@abs(calibration.scale[axis]) <= 1.0e-18) return error.UnobservableAxis;
        const intercept = mean_y - calibration.scale[axis] * mean_x;
        calibration.bias[axis] = -intercept / calibration.scale[axis];
    }
    try calibration.validate();
    return calibration;
}

pub const identity_mount: Mat3 = .{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
};

test "sensor calibration recovers bias and scale" {
    const raw = [_]Vec3{
        .{ 1.0, -2.0, 4.0 },
        .{ 2.0, 0.0, 6.0 },
        .{ 3.0, 2.0, 8.0 },
        .{ 4.0, 4.0, 10.0 },
    };
    var reference: [4]Vec3 = undefined;
    for (raw, 0..) |sample, i| {
        reference[i] = .{
            2.0 * (sample[0] - 0.5),
            0.5 * (sample[1] + 1.0),
            1.5 * (sample[2] - 2.0),
        };
    }
    const fit = try fitBiasScale(&raw, &reference, identity_mount);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), fit.bias[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0), fit.bias[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), fit.scale[2], 1.0e-12);

    const yaw_quarter_turn: SensorCalibration = .{
        .bias = .{ 0, 0, 0 },
        .scale = .{ 1, 1, 1 },
        .sensor_to_body = .{
            .{ 0, -1, 0 },
            .{ 1, 0, 0 },
            .{ 0, 0, 1 },
        },
    };
    const mounted = try yaw_quarter_turn.apply(.{ 1, 0, 0 });
    try std.testing.expectEqual(@as(f64, 0), mounted[0]);
    try std.testing.expectEqual(@as(f64, 1), mounted[1]);
}
