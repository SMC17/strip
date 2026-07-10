//! Small, dependency-free OLS/WLS for bounded flight-identification problems.
const std = @import("std");

pub const max_parameters = 8;
pub const max_observations = 100_000;
pub const Vector = [max_parameters]f64;
pub const Matrix = [max_parameters][max_parameters]f64;

pub const Method = enum { ordinary, weighted };

pub const Fit = struct {
    method: Method,
    parameter_count: usize,
    observation_count: usize,
    coefficients: Vector,
    covariance: Matrix,
    weighted_residual_sum_squares: f64,
    residual_variance: f64,
    rank: usize,
    condition_signal: f64,
    observable: bool,
};

/// `design` is row-major with `observations * parameters` entries.
/// WLS weights are inverse variances and must be positive.
pub fn leastSquares(
    design: []const f64,
    response: []const f64,
    parameters: usize,
    weights: ?[]const f64,
) !Fit {
    if (parameters == 0 or parameters > max_parameters) return error.InvalidParameterCount;
    if (response.len < parameters or response.len > max_observations)
        return error.InvalidObservationCount;
    if (design.len != response.len * parameters) return error.DimensionMismatch;
    if (weights) |provided| if (provided.len != response.len) return error.DimensionMismatch;

    var normal: Matrix = std.mem.zeroes(Matrix);
    var rhs: Vector = std.mem.zeroes(Vector);
    for (response, 0..) |y, row| {
        if (!std.math.isFinite(y)) return error.NonFiniteInput;
        const weight = if (weights) |provided| provided[row] else 1.0;
        if (!std.math.isFinite(weight) or weight <= 0.0) return error.InvalidWeight;
        for (0..parameters) |column| {
            const x = design[row * parameters + column];
            if (!std.math.isFinite(x)) return error.NonFiniteInput;
            rhs[column] += weight * x * y;
            for (0..parameters) |other|
                normal[column][other] += weight * x * design[row * parameters + other];
        }
    }

    var augmented: [max_parameters][max_parameters * 2 + 1]f64 =
        std.mem.zeroes([max_parameters][max_parameters * 2 + 1]f64);
    var largest_entry: f64 = 0.0;
    for (0..parameters) |row| {
        for (0..parameters) |column| {
            largest_entry = @max(largest_entry, @abs(normal[row][column]));
        }
    }
    const threshold = @max(1.0e-14, largest_entry * 1.0e-12);
    for (0..parameters) |row| {
        for (0..parameters) |column| {
            augmented[row][column] = normal[row][column];
            augmented[row][parameters + column] = if (row == column) 1.0 else 0.0;
        }
        augmented[row][2 * parameters] = rhs[row];
    }

    var rank: usize = 0;
    var smallest_pivot = std.math.inf(f64);
    var largest_pivot: f64 = 0.0;
    for (0..parameters) |column| {
        var pivot_row = column;
        var pivot_magnitude = @abs(augmented[column][column]);
        for (column + 1..parameters) |candidate| {
            const magnitude = @abs(augmented[candidate][column]);
            if (magnitude > pivot_magnitude) {
                pivot_magnitude = magnitude;
                pivot_row = candidate;
            }
        }
        if (pivot_magnitude <= threshold) continue;
        if (pivot_row != column) {
            const temporary = augmented[column];
            augmented[column] = augmented[pivot_row];
            augmented[pivot_row] = temporary;
        }
        rank += 1;
        smallest_pivot = @min(smallest_pivot, pivot_magnitude);
        largest_pivot = @max(largest_pivot, pivot_magnitude);
        const pivot = augmented[column][column];
        for (0..2 * parameters + 1) |entry| augmented[column][entry] /= pivot;
        for (0..parameters) |row| {
            if (row == column) continue;
            const factor = augmented[row][column];
            for (0..2 * parameters + 1) |entry|
                augmented[row][entry] -= factor * augmented[column][entry];
        }
    }

    var fit: Fit = .{
        .method = if (weights == null) .ordinary else .weighted,
        .parameter_count = parameters,
        .observation_count = response.len,
        .coefficients = std.mem.zeroes(Vector),
        .covariance = std.mem.zeroes(Matrix),
        .weighted_residual_sum_squares = std.math.inf(f64),
        .residual_variance = std.math.inf(f64),
        .rank = rank,
        .condition_signal = if (rank == 0) std.math.inf(f64) else largest_pivot / smallest_pivot,
        .observable = rank == parameters,
    };
    if (!fit.observable) return fit;
    for (0..parameters) |row| fit.coefficients[row] = augmented[row][2 * parameters];

    var wrss: f64 = 0.0;
    for (response, 0..) |y, row| {
        var predicted: f64 = 0.0;
        for (0..parameters) |column|
            predicted += design[row * parameters + column] * fit.coefficients[column];
        const residual = y - predicted;
        const weight = if (weights) |provided| provided[row] else 1.0;
        wrss += weight * residual * residual;
    }
    fit.weighted_residual_sum_squares = wrss;
    const degrees_of_freedom = response.len - parameters;
    fit.residual_variance = if (degrees_of_freedom > 0)
        wrss / @as(f64, @floatFromInt(degrees_of_freedom))
    else
        0.0;
    for (0..parameters) |row| {
        for (0..parameters) |column| {
            fit.covariance[row][column] =
                augmented[row][parameters + column] * fit.residual_variance;
        }
    }
    return fit;
}

test "synthetic weighted parameter recovery includes covariance and observability" {
    const x = [_]f64{
        1, -2,
        1, -1,
        1, 0,
        1, 1,
        1, 2,
    };
    const y = [_]f64{ -3, -1, 1, 3, 5 };
    const weights = [_]f64{ 1, 2, 3, 2, 1 };
    const fit = try leastSquares(&x, &y, 2, &weights);
    try std.testing.expect(fit.observable);
    try std.testing.expectEqual(@as(usize, 2), fit.rank);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), fit.coefficients[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), fit.coefficients[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), fit.weighted_residual_sum_squares, 1.0e-12);
    try std.testing.expect(std.math.isFinite(fit.condition_signal));

    const ordinary = try leastSquares(&x, &y, 2, null);
    try std.testing.expectEqual(Method.ordinary, ordinary.method);
    try std.testing.expect(ordinary.observable);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), ordinary.coefficients[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), ordinary.coefficients[1], 1.0e-12);
}

test "rank deficient design reports unobservable without pretending covariance" {
    const x = [_]f64{
        1, 2,
        2, 4,
        3, 6,
    };
    const fit = try leastSquares(&x, &.{ 1, 2, 3 }, 2, null);
    try std.testing.expect(!fit.observable);
    try std.testing.expect(fit.rank < fit.parameter_count);
}
