//! Shared synthetic linear coefficient model for cross-implementation gates.

const std = @import("std");
const coefficients = @import("coefficients.zig");

const Storage = struct {
    var alpha: [5]f64 = .{ -0.2, -0.1, 0.0, 0.1, 0.2 };
    var beta: [3]f64 = .{ -0.05, 0.0, 0.05 };
    var mach: [2]f64 = .{ 0.0, 0.3 };
    var values: [30]coefficients.Six = undefined;
    var initialized = false;

    fn initOnce() void {
        if (initialized) return;
        var index: usize = 0;
        for (alpha) |a| {
            for (beta) |b| {
                for (mach) |_| {
                    values[index] = .{
                        .cx = -0.04,
                        .cy = -b,
                        .cz = -4.0 * a,
                        .cl = 0.0,
                        .cm = -0.5 * a,
                        .cn = 0.0,
                    };
                    index += 1;
                }
            }
        }
        initialized = true;
    }
};

pub fn syntheticLinearModel() coefficients.Model {
    Storage.initOnce();
    return .{
        .grid = .{
            .alpha_rad = &Storage.alpha,
            .beta_rad = &Storage.beta,
            .mach = &Storage.mach,
            .values = &Storage.values,
        },
    };
}

test "synthetic linear model matches analytic relations" {
    const model = syntheticLinearModel();
    const value = try model.grid.evaluate(0.1, 0.0, 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, -0.04), value.cx, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, -0.4), value.cz, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, -0.05), value.cm, 1e-14);
}
