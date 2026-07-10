//! Uncertainty propagation beyond status-only representation.

const std = @import("std");
const status = @import("status.zig");
const distribution = @import("distribution.zig");

pub const Propagated = struct {
    value: f64,
    uncertainty: status.Uncertainty,

    pub fn validate(self: Propagated) error{InvalidPropagated}!void {
        if (!std.math.isFinite(self.value)) return error.InvalidPropagated;
        self.uncertainty.validate() catch return error.InvalidPropagated;
    }
};

pub fn fromGaussian(value: f64, model: distribution.Gaussian) error{InvalidPropagated}!Propagated {
    model.validate() catch return error.InvalidPropagated;
    return .{
        .value = value,
        .uncertainty = .{
            .status = .quantified,
            .kind = .standard_deviation,
            .value = model.standardDeviation(),
            .unit = null,
        },
    };
}

pub fn fromInterval(value: f64, model: distribution.Interval) error{InvalidPropagated}!Propagated {
    model.validate() catch return error.InvalidPropagated;
    return .{
        .value = value,
        .uncertainty = .{
            .status = .bounded,
            .kind = .absolute_bound,
            .value = 0.5 * model.width(),
            .unit = null,
        },
    };
}

pub fn linear(
    sensitivity: f64,
    input: Propagated,
    offset: f64,
) error{InvalidPropagated}!Propagated {
    input.validate() catch return error.InvalidPropagated;
    if (!std.math.isFinite(sensitivity) or !std.math.isFinite(offset)) return error.InvalidPropagated;

    const value = sensitivity * input.value + offset;
    const uncertainty: status.Uncertainty = switch (input.uncertainty.status) {
        .quantified, .estimated => blk: {
            const sigma = input.uncertainty.value orelse return error.InvalidPropagated;
            break :blk .{
                .status = input.uncertainty.status,
                .kind = input.uncertainty.kind,
                .value = @abs(sensitivity) * sigma,
                .unit = input.uncertainty.unit,
                .confidence = input.uncertainty.confidence,
            };
        },
        .bounded => blk: {
            const bound = input.uncertainty.value orelse return error.InvalidPropagated;
            break :blk .{
                .status = .bounded,
                .kind = .absolute_bound,
                .value = @abs(sensitivity) * bound,
                .unit = input.uncertainty.unit,
            };
        },
        .unknown, .not_applicable => return error.InvalidPropagated,
    };
    return .{ .value = value, .uncertainty = uncertainty };
}

pub fn independentSum(a: Propagated, b: Propagated) error{InvalidPropagated}!Propagated {
    a.validate() catch return error.InvalidPropagated;
    b.validate() catch return error.InvalidPropagated;
    const value = a.value + b.value;
    const uncertainty: status.Uncertainty = switch (a.uncertainty.status) {
        .quantified => switch (b.uncertainty.status) {
            .quantified => blk: {
                const ga = distribution.Gaussian{
                    .mean = a.value,
                    .variance = std.math.pow(f64, a.uncertainty.value.?, 2),
                };
                const gb = distribution.Gaussian{
                    .mean = b.value,
                    .variance = std.math.pow(f64, b.uncertainty.value.?, 2),
                };
                const sum = ga.independentSum(gb) catch return error.InvalidPropagated;
                break :blk .{
                    .status = .quantified,
                    .kind = .standard_deviation,
                    .value = sum.standardDeviation(),
                    .unit = a.uncertainty.unit,
                };
            },
            else => return error.InvalidPropagated,
        },
        .bounded => switch (b.uncertainty.status) {
            .bounded => blk: {
                const ia = distribution.Interval{
                    .lower = a.value - a.uncertainty.value.?,
                    .upper = a.value + a.uncertainty.value.?,
                };
                const ib = distribution.Interval{
                    .lower = b.value - b.uncertainty.value.?,
                    .upper = b.value + b.uncertainty.value.?,
                };
                const sum = ia.independentSum(ib) catch return error.InvalidPropagated;
                break :blk .{
                    .status = .bounded,
                    .kind = .absolute_bound,
                    .value = 0.5 * sum.width(),
                    .unit = a.uncertainty.unit,
                };
            },
            else => return error.InvalidPropagated,
        },
        else => return error.InvalidPropagated,
    };
    return .{ .value = value, .uncertainty = uncertainty };
}

pub fn composeAffine(
    sensitivities: []const f64,
    inputs: []const Propagated,
    offset: f64,
) error{InvalidPropagated}!Propagated {
    if (sensitivities.len != inputs.len or sensitivities.len == 0) return error.InvalidPropagated;
    var value = offset;
    var variance: f64 = 0;
    for (sensitivities, inputs) |gain, input| {
        input.validate() catch return error.InvalidPropagated;
        if (!std.math.isFinite(gain)) return error.InvalidPropagated;
        value += gain * input.value;
        if (input.uncertainty.status != .quantified) return error.InvalidPropagated;
        const sigma = input.uncertainty.value orelse return error.InvalidPropagated;
        variance += gain * gain * sigma * sigma;
    }
    return .{
        .value = value,
        .uncertainty = .{
            .status = .quantified,
            .kind = .standard_deviation,
            .value = @sqrt(variance),
            .unit = null,
        },
    };
}

test "linear propagation scales standard deviation" {
    const input = try fromGaussian(10.0, .{ .mean = 10.0, .variance = 0.04 });
    const output = try linear(2.0, input, -1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 19.0), output.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4), output.uncertainty.value.?, 1e-12);
}

test "independent sum combines gaussian variances" {
    const a = try fromGaussian(1.0, .{ .mean = 1.0, .variance = 1.0 });
    const b = try fromGaussian(2.0, .{ .mean = 2.0, .variance = 3.0 });
    const sum = try independentSum(a, b);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), sum.value, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), sum.uncertainty.value.?, 1e-12);
}

test "compose affine matches manual two-input linear sum" {
    const x = try fromGaussian(1.0, .{ .mean = 1.0, .variance = 0.01 });
    const y = try fromGaussian(2.0, .{ .mean = 2.0, .variance = 0.04 });
    const composed = try composeAffine(&.{ 3.0, -0.5 }, &.{ x, y }, 1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), composed.value, 1e-12);
    try std.testing.expect(composed.uncertainty.value.? > 0.0);
}
