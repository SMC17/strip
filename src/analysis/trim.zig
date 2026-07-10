//! Bounded Newton trim residual solver with finite-difference Jacobian.

const std = @import("std");

pub const Variables = struct {
    alpha_rad: f64,
    elevator_rad: f64,
    throttle: f64,

    fn array(self: Variables) [3]f64 {
        return .{ self.alpha_rad, self.elevator_rad, self.throttle };
    }

    fn fromArray(value: [3]f64) Variables {
        return .{ .alpha_rad = value[0], .elevator_rad = value[1], .throttle = value[2] };
    }
};

pub const Bounds = struct {
    minimum: Variables,
    maximum: Variables,
};

pub const ResidualFn = *const fn (context: *const anyopaque, variables: Variables) anyerror![3]f64;

pub const Options = struct {
    tolerance: f64 = 1e-8,
    finite_difference_step: f64 = 1e-5,
    maximum_iterations: u32 = 30,
};

pub const Result = struct {
    variables: Variables,
    residual: [3]f64,
    iterations: u32,
};

pub fn solve(
    context: *const anyopaque,
    residual_fn: ResidualFn,
    initial: Variables,
    bounds: Bounds,
    options: Options,
) !Result {
    if (!(options.tolerance > 0.0) or !(options.finite_difference_step > 0.0) or
        options.maximum_iterations == 0) return error.InvalidOptions;
    const lower = bounds.minimum.array();
    const upper = bounds.maximum.array();
    var x = initial.array();
    for (0..3) |i| {
        if (!(lower[i] <= x[i] and x[i] <= upper[i])) return error.InitialOutsideBounds;
    }

    var iteration: u32 = 0;
    while (iteration < options.maximum_iterations) : (iteration += 1) {
        const residual = try residual_fn(context, Variables.fromArray(x));
        if (maxAbs(residual) <= options.tolerance)
            return .{ .variables = Variables.fromArray(x), .residual = residual, .iterations = iteration };
        var jacobian: [3][3]f64 = undefined;
        for (0..3) |column| {
            var perturbed = x;
            const room = upper[column] - lower[column];
            const step = @min(options.finite_difference_step, 0.25 * room);
            if (!(step > 0.0)) return error.DegenerateBounds;
            var signed_step = step;
            if (x[column] + step > upper[column]) signed_step = -step;
            perturbed[column] += signed_step;
            const shifted = try residual_fn(context, Variables.fromArray(perturbed));
            for (0..3) |row| jacobian[row][column] = (shifted[row] - residual[row]) / signed_step;
        }
        const delta = solve3(jacobian, .{ -residual[0], -residual[1], -residual[2] }) catch
            return error.SingularJacobian;

        // Damped, projected Newton step keeps every evaluation inside bounds.
        var damping: f64 = 1.0;
        for (0..3) |i| {
            if (delta[i] > 0.0) damping = @min(damping, (upper[i] - x[i]) / delta[i]);
            if (delta[i] < 0.0) damping = @min(damping, (lower[i] - x[i]) / delta[i]);
        }
        damping = @min(1.0, 0.95 * damping);
        if (!(damping > 1e-12)) return error.BoundStagnation;
        for (0..3) |i| x[i] += damping * delta[i];
    }
    return error.NoConvergence;
}

fn maxAbs(values: [3]f64) f64 {
    return @max(@abs(values[0]), @max(@abs(values[1]), @abs(values[2])));
}

fn solve3(matrix: [3][3]f64, rhs: [3]f64) error{Singular}![3]f64 {
    var a: [3][4]f64 = undefined;
    for (0..3) |row| {
        for (0..3) |column| a[row][column] = matrix[row][column];
        a[row][3] = rhs[row];
    }
    for (0..3) |pivot_column| {
        var pivot = pivot_column;
        for (pivot_column + 1..3) |row| {
            if (@abs(a[row][pivot_column]) > @abs(a[pivot][pivot_column])) pivot = row;
        }
        if (@abs(a[pivot][pivot_column]) < 1e-14) return error.Singular;
        if (pivot != pivot_column) {
            const temporary = a[pivot];
            a[pivot] = a[pivot_column];
            a[pivot_column] = temporary;
        }
        const divisor = a[pivot_column][pivot_column];
        for (pivot_column..4) |column| a[pivot_column][column] /= divisor;
        for (0..3) |row| {
            if (row == pivot_column) continue;
            const factor = a[row][pivot_column];
            for (pivot_column..4) |column| a[row][column] -= factor * a[pivot_column][column];
        }
    }
    return .{ a[0][3], a[1][3], a[2][3] };
}

fn syntheticResidual(_: *const anyopaque, variables: Variables) ![3]f64 {
    return .{
        variables.alpha_rad + variables.elevator_rad - 0.1,
        2.0 * variables.alpha_rad - variables.elevator_rad - 0.2,
        variables.throttle * variables.throttle - 0.25,
    };
}

test "trim solver converges on bounded synthetic residual" {
    const context: u8 = 0;
    const result = try solve(&context, syntheticResidual, .{
        .alpha_rad = 0.08,
        .elevator_rad = 0.01,
        .throttle = 0.4,
    }, .{
        .minimum = .{ .alpha_rad = -0.2, .elevator_rad = -0.3, .throttle = 0.0 },
        .maximum = .{ .alpha_rad = 0.3, .elevator_rad = 0.3, .throttle = 1.0 },
    }, .{});
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), result.variables.alpha_rad, 1e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.variables.elevator_rad, 1e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result.variables.throttle, 1e-7);
}
