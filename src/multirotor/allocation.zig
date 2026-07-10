//! Deterministic bounded control allocation for up to eight vertical rotors.

const std = @import("std");
const propulsion = @import("propulsion.zig");
const math = @import("math.zig");

pub const Demand = struct {
    thrust_n: f64,
    moment_body_nm: math.Vec3,
};

pub const RotorGeometry = struct {
    position_body_m: math.Vec3,
    direction: propulsion.Direction,
    reaction_torque_per_thrust_m: f64,
    maximum_thrust_n: f64,
    enabled: bool = true,

    fn column(self: RotorGeometry) [4]f64 {
        return .{
            1.0,
            -self.position_body_m.y,
            self.position_body_m.x,
            self.direction.sign() * self.reaction_torque_per_thrust_m,
        };
    }
};

pub const Result = struct {
    thrust_n: [propulsion.max_rotors]f64,
    command_fraction: [propulsion.max_rotors]f64,
    achieved: Demand,
    rotor_count: usize,
    rank: u8,
    rank_loss: bool,
    saturated: bool,
    residual_norm: f64,
};

pub fn allocate(
    rotors: []const RotorGeometry,
    demand: Demand,
) error{ InvalidGeometry, InvalidDemand }!Result {
    if (rotors.len == 0 or rotors.len > propulsion.max_rotors) return error.InvalidGeometry;
    const target = [4]f64{
        demand.thrust_n,
        demand.moment_body_nm.x,
        demand.moment_body_nm.y,
        demand.moment_body_nm.z,
    };
    for (target) |value| if (!std.math.isFinite(value)) return error.InvalidDemand;

    var columns: [propulsion.max_rotors][4]f64 = undefined;
    var enabled: [propulsion.max_rotors]bool = @splat(false);
    for (rotors, 0..) |rotor, index| {
        if (!rotor.position_body_m.isFinite() or
            !std.math.isFinite(rotor.reaction_torque_per_thrust_m) or
            rotor.reaction_torque_per_thrust_m < 0.0 or
            !std.math.isFinite(rotor.maximum_thrust_n) or !(rotor.maximum_thrust_n > 0.0))
            return error.InvalidGeometry;
        columns[index] = rotor.column();
        enabled[index] = rotor.enabled;
    }

    const system_rank = matrixRank(columns[0..rotors.len], enabled[0..rotors.len]);
    var free = enabled;
    var thrust: [propulsion.max_rotors]f64 = @splat(0.0);
    var clipped = false;

    // Bounded active-set least squares. Once a rotor reaches a bound it remains fixed.
    for (0..propulsion.max_rotors + 1) |_| {
        var residual = target;
        for (rotors, 0..) |_, index| {
            if (free[index]) continue;
            for (0..4) |row| residual[row] -= columns[index][row] * thrust[index];
        }
        const solution = leastSquares(columns[0..rotors.len], free[0..rotors.len], residual);
        var changed = false;
        for (rotors, 0..) |rotor, index| {
            if (!free[index]) continue;
            const proposed = solution[index];
            if (proposed < 0.0) {
                thrust[index] = 0.0;
                free[index] = false;
                changed = true;
                clipped = true;
            } else if (proposed > rotor.maximum_thrust_n) {
                thrust[index] = rotor.maximum_thrust_n;
                free[index] = false;
                changed = true;
                clipped = true;
            } else {
                thrust[index] = proposed;
            }
        }
        if (!changed) break;
    }

    var achieved_vector: [4]f64 = @splat(0.0);
    var commands: [propulsion.max_rotors]f64 = @splat(0.0);
    for (rotors, 0..) |rotor, index| {
        for (0..4) |row| achieved_vector[row] += columns[index][row] * thrust[index];
        commands[index] = @sqrt(std.math.clamp(thrust[index] / rotor.maximum_thrust_n, 0.0, 1.0));
    }
    var residual_squared: f64 = 0.0;
    for (0..4) |row| {
        const difference = target[row] - achieved_vector[row];
        residual_squared += difference * difference;
    }
    const residual_norm = @sqrt(residual_squared);
    const scale = @max(1.0, @abs(demand.thrust_n));

    return .{
        .thrust_n = thrust,
        .command_fraction = commands,
        .achieved = .{
            .thrust_n = achieved_vector[0],
            .moment_body_nm = .{
                .x = achieved_vector[1],
                .y = achieved_vector[2],
                .z = achieved_vector[3],
            },
        },
        .rotor_count = rotors.len,
        .rank = system_rank,
        .rank_loss = system_rank < 4,
        .saturated = clipped or residual_norm > 1e-9 * scale,
        .residual_norm = residual_norm,
    };
}

fn leastSquares(
    columns: []const [4]f64,
    free: []const bool,
    target: [4]f64,
) [propulsion.max_rotors]f64 {
    var normal: [4][5]f64 = @splat(@splat(0.0));
    for (0..4) |row| {
        normal[row][4] = target[row];
        // Tiny damping makes degraded/rank-deficient cases deterministic and bounded.
        normal[row][row] = 1e-12;
        for (columns, 0..) |column, index| {
            if (!free[index]) continue;
            for (0..4) |other| normal[row][other] += column[row] * column[other];
        }
    }
    gaussJordan(&normal);

    var result: [propulsion.max_rotors]f64 = @splat(0.0);
    for (columns, 0..) |column, index| {
        if (!free[index]) continue;
        for (0..4) |row| result[index] += column[row] * normal[row][4];
    }
    return result;
}

fn gaussJordan(matrix: *[4][5]f64) void {
    for (0..4) |pivot_column| {
        var pivot_row = pivot_column;
        for (pivot_column + 1..4) |candidate| {
            if (@abs(matrix[candidate][pivot_column]) > @abs(matrix[pivot_row][pivot_column]))
                pivot_row = candidate;
        }
        if (pivot_row != pivot_column) std.mem.swap([5]f64, &matrix[pivot_row], &matrix[pivot_column]);
        const pivot = matrix[pivot_column][pivot_column];
        if (@abs(pivot) <= 1e-20) continue;
        for (pivot_column..5) |column| matrix[pivot_column][column] /= pivot;
        for (0..4) |row| {
            if (row == pivot_column) continue;
            const multiplier = matrix[row][pivot_column];
            for (pivot_column..5) |column| matrix[row][column] -= multiplier * matrix[pivot_column][column];
        }
    }
}

fn matrixRank(columns: []const [4]f64, enabled: []const bool) u8 {
    var matrix: [4][propulsion.max_rotors]f64 = @splat(@splat(0.0));
    for (columns, 0..) |column, index| {
        if (!enabled[index]) continue;
        for (0..4) |row| matrix[row][index] = column[row];
    }
    var rank: u8 = 0;
    var pivot_column: usize = 0;
    while (rank < 4 and pivot_column < columns.len) : (pivot_column += 1) {
        var pivot_row: ?usize = null;
        for (@as(usize, rank)..4) |row| {
            if (@abs(matrix[row][pivot_column]) > 1e-10) {
                pivot_row = row;
                break;
            }
        }
        if (pivot_row == null) continue;
        const row_index: usize = rank;
        if (pivot_row.? != row_index)
            std.mem.swap([propulsion.max_rotors]f64, &matrix[pivot_row.?], &matrix[row_index]);
        const pivot = matrix[row_index][pivot_column];
        for (pivot_column..columns.len) |column| matrix[row_index][column] /= pivot;
        for (0..4) |row| {
            if (row == row_index) continue;
            const multiplier = matrix[row][pivot_column];
            for (pivot_column..columns.len) |column| matrix[row][column] -= multiplier * matrix[row_index][column];
        }
        rank += 1;
    }
    return rank;
}

fn quad() [4]RotorGeometry {
    return .{
        .{ .position_body_m = .{ .x = 0.2, .y = -0.2, .z = 0.0 }, .direction = .counter_clockwise, .reaction_torque_per_thrust_m = 0.02, .maximum_thrust_n = 10.0 },
        .{ .position_body_m = .{ .x = 0.2, .y = 0.2, .z = 0.0 }, .direction = .clockwise, .reaction_torque_per_thrust_m = 0.02, .maximum_thrust_n = 10.0 },
        .{ .position_body_m = .{ .x = -0.2, .y = 0.2, .z = 0.0 }, .direction = .counter_clockwise, .reaction_torque_per_thrust_m = 0.02, .maximum_thrust_n = 10.0 },
        .{ .position_body_m = .{ .x = -0.2, .y = -0.2, .z = 0.0 }, .direction = .clockwise, .reaction_torque_per_thrust_m = 0.02, .maximum_thrust_n = 10.0 },
    };
}

test "hover closes and reaction torques cancel" {
    const result = try allocate(&quad(), .{ .thrust_n = 20.0, .moment_body_nm = math.Vec3.zero });
    try std.testing.expect(!result.rank_loss);
    try std.testing.expect(!result.saturated);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), result.achieved.thrust_n, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.achieved.moment_body_nm.z, 1e-10);
    for (result.thrust_n[0..4]) |value| try std.testing.expectApproxEqAbs(@as(f64, 5.0), value, 1e-9);
}

test "roll pitch yaw demands preserve requested signs" {
    const demands = [_]Demand{
        .{ .thrust_n = 20.0, .moment_body_nm = .{ .x = 0.2, .y = 0.0, .z = 0.0 } },
        .{ .thrust_n = 20.0, .moment_body_nm = .{ .x = 0.0, .y = -0.2, .z = 0.0 } },
        .{ .thrust_n = 20.0, .moment_body_nm = .{ .x = 0.0, .y = 0.0, .z = 0.02 } },
    };
    for (demands) |demand| {
        const result = try allocate(&quad(), demand);
        try std.testing.expect(!result.saturated);
        if (demand.moment_body_nm.x != 0.0) try std.testing.expect(result.achieved.moment_body_nm.x > 0.0);
        if (demand.moment_body_nm.y != 0.0) try std.testing.expect(result.achieved.moment_body_nm.y < 0.0);
        if (demand.moment_body_nm.z != 0.0) try std.testing.expect(result.achieved.moment_body_nm.z > 0.0);
    }
}

test "saturation and rotor-out are explicit and deterministic" {
    const saturated = try allocate(&quad(), .{ .thrust_n = 100.0, .moment_body_nm = math.Vec3.zero });
    try std.testing.expect(saturated.saturated);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), saturated.achieved.thrust_n, 1e-9);

    var failed = quad();
    failed[0].enabled = false;
    const first = try allocate(&failed, .{ .thrust_n = 20.0, .moment_body_nm = math.Vec3.zero });
    const second = try allocate(&failed, .{ .thrust_n = 20.0, .moment_body_nm = math.Vec3.zero });
    try std.testing.expect(first.rank_loss);
    try std.testing.expect(first.saturated);
    try std.testing.expectEqual(@as(f64, 0.0), first.thrust_n[0]);
    try std.testing.expectEqualDeep(first, second);
}
