//! Finite-difference state-space linearization and bounded modal summaries.
//! Longitudinal state ordering is [u, w, q, theta], controls [elevator, throttle].

const std = @import("std");

pub const State = [4]f64;
pub const Controls = [2]f64;
pub const DynamicsFn = *const fn (*const anyopaque, State, Controls) anyerror!State;

pub const StateSpace = struct {
    a: [4][4]f64,
    b: [4][2]f64,
};

pub fn finiteDifference(
    context: *const anyopaque,
    dynamics_fn: DynamicsFn,
    state: State,
    controls: Controls,
    step: f64,
) !StateSpace {
    if (!std.math.isFinite(step) or !(step > 0.0)) return error.InvalidStep;
    var output: StateSpace = undefined;
    for (0..4) |column| {
        var plus = state;
        var minus = state;
        plus[column] += step;
        minus[column] -= step;
        const f_plus = try dynamics_fn(context, plus, controls);
        const f_minus = try dynamics_fn(context, minus, controls);
        for (0..4) |row| output.a[row][column] = (f_plus[row] - f_minus[row]) / (2.0 * step);
    }
    for (0..2) |column| {
        var plus = controls;
        var minus = controls;
        plus[column] += step;
        minus[column] -= step;
        const f_plus = try dynamics_fn(context, state, plus);
        const f_minus = try dynamics_fn(context, state, minus);
        for (0..4) |row| output.b[row][column] = (f_plus[row] - f_minus[row]) / (2.0 * step);
    }
    return output;
}

pub const Stability = enum { stable, neutral, unstable };

pub const Mode = struct {
    stability: Stability,
    oscillatory: bool,
    real_part_per_s: f64,
    natural_frequency_radps: f64,
    damping_ratio: ?f64,
};

pub const LongitudinalModes = struct {
    /// Approximation from the [u, theta] principal submatrix.
    phugoid: Mode,
    /// Approximation from the [w, q] principal submatrix.
    short_period: Mode,
};

pub fn classifyLongitudinal(matrix: [4][4]f64) LongitudinalModes {
    return .{
        .phugoid = classifyPair(matrix, 0, 3),
        .short_period = classifyPair(matrix, 1, 2),
    };
}

fn classifyPair(matrix: [4][4]f64, first: usize, second: usize) Mode {
    const trace = matrix[first][first] + matrix[second][second];
    const determinant = matrix[first][first] * matrix[second][second] -
        matrix[first][second] * matrix[second][first];
    const discriminant = trace * trace - 4.0 * determinant;
    const real_part = 0.5 * trace;
    const stability: Stability = if (real_part < -1e-10) .stable else if (real_part > 1e-10) .unstable else .neutral;
    if (discriminant < 0.0) {
        const natural_frequency = @sqrt(@max(0.0, determinant));
        return .{
            .stability = stability,
            .oscillatory = true,
            .real_part_per_s = real_part,
            .natural_frequency_radps = natural_frequency,
            .damping_ratio = if (natural_frequency > 0.0) -real_part / natural_frequency else null,
        };
    }
    const root = @sqrt(discriminant);
    const lambda_a = 0.5 * (trace + root);
    const lambda_b = 0.5 * (trace - root);
    const real_stability: Stability = if (@max(lambda_a, lambda_b) < -1e-10)
        .stable
    else if (@max(lambda_a, lambda_b) > 1e-10)
        .unstable
    else
        .neutral;
    return .{
        .stability = real_stability,
        .oscillatory = false,
        .real_part_per_s = @max(lambda_a, lambda_b),
        .natural_frequency_radps = @sqrt(@abs(determinant)),
        .damping_ratio = null,
    };
}

const LinearContext = struct {
    a: [4][4]f64,
    b: [4][2]f64,
};

fn linearDynamics(raw: *const anyopaque, state: State, controls: Controls) !State {
    const context: *const LinearContext = @ptrCast(@alignCast(raw));
    var result = [_]f64{0.0} ** 4;
    for (0..4) |row| {
        for (0..4) |column| result[row] += context.a[row][column] * state[column];
        for (0..2) |column| result[row] += context.b[row][column] * controls[column];
    }
    return result;
}

test "finite difference recovers synthetic linear dynamics and classifies modes" {
    const context = LinearContext{
        .a = .{
            .{ -0.05, 0.0, 0.0, -0.2 },
            .{ 0.0, -1.0, 2.0, 0.0 },
            .{ 0.0, -2.0, -1.0, 0.0 },
            .{ 0.2, 0.0, 0.0, -0.05 },
        },
        .b = .{
            .{ 0.0, 1.0 }, .{ 2.0, 0.0 }, .{ 3.0, 0.0 }, .{ 0.0, 0.0 },
        },
    };
    const system = try finiteDifference(&context, linearDynamics, .{ 10.0, 0.1, 0.0, 0.02 }, .{ 0.0, 0.5 }, 1e-5);
    try std.testing.expectApproxEqAbs(context.a[1][2], system.a[1][2], 1e-9);
    try std.testing.expectApproxEqAbs(context.b[0][1], system.b[0][1], 1e-9);
    const modes = classifyLongitudinal(system.a);
    try std.testing.expect(modes.phugoid.oscillatory);
    try std.testing.expectEqual(Stability.stable, modes.phugoid.stability);
    try std.testing.expect(modes.short_period.oscillatory);
    try std.testing.expectEqual(Stability.stable, modes.short_period.stability);
    try std.testing.expect(modes.short_period.natural_frequency_radps > modes.phugoid.natural_frequency_radps);
}
