//! Elementary uncertainty distributions for propagation.

const std = @import("std");

pub const Gaussian = struct {
    mean: f64,
    variance: f64,

    pub fn validate(self: Gaussian) error{InvalidDistribution}!void {
        if (!std.math.isFinite(self.mean) or !std.math.isFinite(self.variance) or self.variance < 0.0)
            return error.InvalidDistribution;
    }

    pub fn standardDeviation(self: Gaussian) f64 {
        return @sqrt(self.variance);
    }

    pub fn independentSum(a: Gaussian, b: Gaussian) error{InvalidDistribution}!Gaussian {
        try a.validate();
        try b.validate();
        return .{ .mean = a.mean + b.mean, .variance = a.variance + b.variance };
    }

    pub fn affine(self: Gaussian, scale: f64, offset: f64) error{InvalidDistribution}!Gaussian {
        try self.validate();
        if (!std.math.isFinite(scale) or !std.math.isFinite(offset)) return error.InvalidDistribution;
        return .{ .mean = scale * self.mean + offset, .variance = scale * scale * self.variance };
    }
};

pub const Interval = struct {
    lower: f64,
    upper: f64,

    pub fn validate(self: Interval) error{InvalidDistribution}!void {
        if (!std.math.isFinite(self.lower) or !std.math.isFinite(self.upper) or self.lower > self.upper)
            return error.InvalidDistribution;
    }

    pub fn width(self: Interval) f64 {
        return self.upper - self.lower;
    }

    pub fn independentSum(a: Interval, b: Interval) error{InvalidDistribution}!Interval {
        try a.validate();
        try b.validate();
        return .{ .lower = a.lower + b.lower, .upper = a.upper + b.upper };
    }

    pub fn independentProduct(a: Interval, b: Interval) error{InvalidDistribution}!Interval {
        try a.validate();
        try b.validate();
        const products = [_]f64{ a.lower * b.lower, a.lower * b.upper, a.upper * b.lower, a.upper * b.upper };
        var lower = products[0];
        var upper = products[0];
        for (products[1..]) |value| {
            lower = @min(lower, value);
            upper = @max(upper, value);
        }
        return .{ .lower = lower, .upper = upper };
    }
};

test "gaussian independent sum accumulates variance" {
    const a = Gaussian{ .mean = 1.0, .variance = 0.25 };
    const b = Gaussian{ .mean = 2.0, .variance = 0.75 };
    const sum = try a.independentSum(b);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), sum.mean, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sum.variance, 1e-12);
}

test "interval product covers extrema" {
    const a = Interval{ .lower = -1.0, .upper = 2.0 };
    const b = Interval{ .lower = 0.5, .upper = 1.5 };
    const product = try a.independentProduct(b);
    try std.testing.expectApproxEqAbs(@as(f64, -1.5), product.lower, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), product.upper, 1e-12);
}
