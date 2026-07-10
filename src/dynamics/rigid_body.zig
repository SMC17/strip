//! Six-degree-of-freedom rigid-body equations and fixed-step RK4 integration.
//! Forces are world-frame, moments and angular rates are body-frame.

const std = @import("std");
const math = @import("math.zig");
const mass_properties = @import("../vehicle/mass_properties.zig");

pub const State = struct {
    position_world_m: math.Vec3,
    velocity_world_mps: math.Vec3,
    body_to_world: math.Quaternion,
    angular_velocity_body_radps: math.Vec3,
};

pub const Wrench = struct {
    force_world_n: math.Vec3 = math.Vec3.zero,
    moment_body_nm: math.Vec3 = math.Vec3.zero,
};

pub const Derivative = struct {
    position_world_mps: math.Vec3,
    velocity_world_mps2: math.Vec3,
    body_to_world_per_s: math.Quaternion,
    angular_velocity_body_radps2: math.Vec3,
};

pub fn derivative(
    state: State,
    properties: mass_properties.MassProperties,
    wrench: Wrench,
    gravity_world_mps2: math.Vec3,
) Derivative {
    const inertia_omega = properties.inertia_kg_m2.multiply(state.angular_velocity_body_radps);
    const gyroscopic_moment = state.angular_velocity_body_radps.cross(inertia_omega);
    return .{
        .position_world_mps = state.velocity_world_mps,
        .velocity_world_mps2 = wrench.force_world_n.scale(1.0 / properties.mass_kg).add(gravity_world_mps2),
        .body_to_world_per_s = math.Quaternion.derivativeBodyRate(
            state.body_to_world,
            state.angular_velocity_body_radps,
        ),
        .angular_velocity_body_radps2 = properties.inertia_kg_m2.solve(
            wrench.moment_body_nm.sub(gyroscopic_moment),
        ),
    };
}

fn advanced(state: State, slope: Derivative, dt: f64) State {
    return .{
        .position_world_m = state.position_world_m.add(slope.position_world_mps.scale(dt)),
        .velocity_world_mps = state.velocity_world_mps.add(slope.velocity_world_mps2.scale(dt)),
        .body_to_world = state.body_to_world.add(slope.body_to_world_per_s.scale(dt)),
        .angular_velocity_body_radps = state.angular_velocity_body_radps.add(
            slope.angular_velocity_body_radps2.scale(dt),
        ),
    };
}

/// One fixed RK4 step. The supplied wrench and gravity are held constant over
/// the step; callers needing state-dependent aerodynamics should substep or
/// provide a higher-level force callback.
pub fn rk4Step(
    state: State,
    properties: mass_properties.MassProperties,
    wrench: Wrench,
    gravity_world_mps2: math.Vec3,
    dt_s: f64,
) error{ InvalidStep, InvalidOrientation }!State {
    if (!(dt_s > 0.0) or !std.math.isFinite(dt_s)) return error.InvalidStep;

    const k1 = derivative(state, properties, wrench, gravity_world_mps2);
    const k2 = derivative(advanced(state, k1, 0.5 * dt_s), properties, wrench, gravity_world_mps2);
    const k3 = derivative(advanced(state, k2, 0.5 * dt_s), properties, wrench, gravity_world_mps2);
    const k4 = derivative(advanced(state, k3, dt_s), properties, wrench, gravity_world_mps2);

    const one_sixth_dt = dt_s / 6.0;
    const weighted = Derivative{
        .position_world_mps = k1.position_world_mps
            .add(k2.position_world_mps.scale(2.0))
            .add(k3.position_world_mps.scale(2.0))
            .add(k4.position_world_mps),
        .velocity_world_mps2 = k1.velocity_world_mps2
            .add(k2.velocity_world_mps2.scale(2.0))
            .add(k3.velocity_world_mps2.scale(2.0))
            .add(k4.velocity_world_mps2),
        .body_to_world_per_s = k1.body_to_world_per_s
            .add(k2.body_to_world_per_s.scale(2.0))
            .add(k3.body_to_world_per_s.scale(2.0))
            .add(k4.body_to_world_per_s),
        .angular_velocity_body_radps2 = k1.angular_velocity_body_radps2
            .add(k2.angular_velocity_body_radps2.scale(2.0))
            .add(k3.angular_velocity_body_radps2.scale(2.0))
            .add(k4.angular_velocity_body_radps2),
    };

    var result = advanced(state, weighted, one_sixth_dt);
    result.body_to_world = result.body_to_world.normalized() catch return error.InvalidOrientation;
    return result;
}

fn testProperties() !mass_properties.MassProperties {
    return mass_properties.MassProperties.init(
        2.0,
        math.Vec3.zero,
        .{ .xx = 3.0, .yy = 3.0, .zz = 3.0 },
    );
}

test "RK4 reproduces constant-acceleration translation" {
    const initial = State{
        .position_world_m = math.Vec3.zero,
        .velocity_world_mps = .{ .x = 2.0, .y = 0.0, .z = 0.0 },
        .body_to_world = math.Quaternion.identity,
        .angular_velocity_body_radps = math.Vec3.zero,
    };
    const result = try rk4Step(
        initial,
        try testProperties(),
        .{ .force_world_n = .{ .x = 0.0, .y = 0.0, .z = 4.0 } },
        .{ .x = 0.0, .y = 0.0, .z = -10.0 },
        0.5,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.position_world_m.x, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0), result.position_world_m.z, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, -4.0), result.velocity_world_mps.z, 1e-12);
}

test "torque-free spherical body keeps angular rate and quaternion norm" {
    const initial = State{
        .position_world_m = math.Vec3.zero,
        .velocity_world_mps = math.Vec3.zero,
        .body_to_world = math.Quaternion.identity,
        .angular_velocity_body_radps = .{ .x = 0.2, .y = -0.1, .z = 0.3 },
    };
    const result = try rk4Step(initial, try testProperties(), .{}, math.Vec3.zero, 0.1);
    try std.testing.expectApproxEqAbs(initial.angular_velocity_body_radps.x, result.angular_velocity_body_radps.x, 1e-14);
    try std.testing.expectApproxEqAbs(initial.angular_velocity_body_radps.y, result.angular_velocity_body_radps.y, 1e-14);
    try std.testing.expectApproxEqAbs(initial.angular_velocity_body_radps.z, result.angular_velocity_body_radps.z, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result.body_to_world.normSquared(), 1e-14);
}
