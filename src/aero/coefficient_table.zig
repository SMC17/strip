//! Validated one-dimensional aerodynamic coefficient interpolation.
//! This is linear interpolation only; extrapolation is always refused.

const std = @import("std");

pub const InitError = error{
    LengthMismatch,
    TooFewPoints,
    NonFinitePoint,
    AbscissaNotStrictlyIncreasing,
};

pub const Evaluation = union(enum) {
    valid: f64,
    outside_envelope,
};

pub const Table1D = struct {
    abscissa: []const f64,
    coefficient: []const f64,

    pub fn init(abscissa: []const f64, coefficient: []const f64) InitError!Table1D {
        if (abscissa.len != coefficient.len) return error.LengthMismatch;
        if (abscissa.len < 2) return error.TooFewPoints;
        for (abscissa, coefficient, 0..) |x, y, index| {
            if (!std.math.isFinite(x) or !std.math.isFinite(y)) return error.NonFinitePoint;
            if (index > 0 and !(x > abscissa[index - 1])) {
                return error.AbscissaNotStrictlyIncreasing;
            }
        }
        return .{ .abscissa = abscissa, .coefficient = coefficient };
    }

    pub fn evaluate(self: Table1D, query: f64) Evaluation {
        if (!std.math.isFinite(query) or query < self.abscissa[0] or query > self.abscissa[self.abscissa.len - 1]) {
            return .outside_envelope;
        }
        if (query == self.abscissa[self.abscissa.len - 1]) {
            return .{ .valid = self.coefficient[self.coefficient.len - 1] };
        }

        var low: usize = 0;
        var high: usize = self.abscissa.len - 1;
        while (high - low > 1) {
            const middle = low + (high - low) / 2;
            if (query < self.abscissa[middle]) {
                high = middle;
            } else {
                low = middle;
            }
        }
        const fraction = (query - self.abscissa[low]) / (self.abscissa[high] - self.abscissa[low]);
        return .{ .valid = self.coefficient[low] + fraction * (self.coefficient[high] - self.coefficient[low]) };
    }
};

test "linear table preserves nodes and interpolates affine data" {
    const x = [_]f64{ -0.2, 0.0, 0.3 };
    const c = [_]f64{ -0.4, 0.0, 0.6 };
    const table = try Table1D.init(&x, &c);
    try std.testing.expectApproxEqAbs(@as(f64, -0.4), table.evaluate(-0.2).valid, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), table.evaluate(0.1).valid, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), table.evaluate(0.3).valid, 1e-14);
}

test "table refuses extrapolation and malformed grids" {
    const x = [_]f64{ 0.0, 1.0 };
    const c = [_]f64{ 0.0, 2.0 };
    const table = try Table1D.init(&x, &c);
    try std.testing.expect(table.evaluate(-0.001) == .outside_envelope);
    try std.testing.expect(table.evaluate(1.001) == .outside_envelope);

    const unordered = [_]f64{ 0.0, 0.0 };
    try std.testing.expectError(error.AbscissaNotStrictlyIncreasing, Table1D.init(&unordered, &c));
}
