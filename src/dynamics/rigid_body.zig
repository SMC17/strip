//! Six-degree-of-freedom rigid-body equations and fixed-step RK4 integration.
//! Forces are world-frame, moments and angular rates are body-frame.

const std = @import("std");
const math = @import("math.zig");
const mass_properties = @import("../vehicle/mass_properties.zig");
const evidence = @import("../evidence.zig");
const numerical_result = @import("../result.zig");

pub const manifest = evidence.ModelManifest{
    .id = "strip.dynamics.rigid-body-rk4",
    .version = "0.2.0",
    .proof_level = .unit_tested,
    .source = "Newton-Euler rigid-body equations with coupled RK4 integration",
    .assumptions = &.{
        "constant mass and inertia over the step",
        "world-frame specific force plus body-frame moments",
    },
    .valid_min = 0.0,
    .valid_max = 3600.0,
    .valid_unit = "s",
};

pub const State = struct {
    position_world_m: math.Vec3,
    velocity_world_mps: math.Vec3,
    body_to_world: math.Quaternion,
    angular_velocity_body_radps: math.Vec3,

    pub fn validate(self: State) error{ NonFiniteState, InvalidOrientation }!void {
        if (!self.position_world_m.isFinite() or
            !self.velocity_world_mps.isFinite() or
            !self.body_to_world.isFinite() or
            !self.angular_velocity_body_radps.isFinite())
            return error.NonFiniteState;
        const orientation_norm_squared = self.body_to_world.normSquared();
        if (!(orientation_norm_squared > 0.0) or !std.math.isFinite(orientation_norm_squared))
            return error.InvalidOrientation;
    }
};

pub const Wrench = struct {
    force_world_n: math.Vec3 = math.Vec3.zero,
    moment_body_nm: math.Vec3 = math.Vec3.zero,

    pub fn isFinite(self: Wrench) bool {
        return self.force_world_n.isFinite() and self.moment_body_nm.isFinite();
    }
};

pub const Loads = struct {
    wrench: Wrench = .{},
    gravity_world_mps2: math.Vec3 = math.Vec3.zero,

    pub fn isFinite(self: Loads) bool {
        return self.wrench.isFinite() and self.gravity_world_mps2.isFinite();
    }
};

/// Evaluated at each RK stage with that stage's time and state.
pub const LoadCallback = struct {
    context: ?*anyopaque = null,
    evaluate: *const fn (?*anyopaque, f64, State) Loads,
};

pub const IntegrationError = error{
    InvalidStep,
    NonFiniteTime,
    NonFiniteState,
    InvalidOrientation,
    NonFiniteLoads,
    NonFiniteDerivative,
};

pub const Derivative = struct {
    position_world_mps: math.Vec3,
    velocity_world_mps2: math.Vec3,
    body_to_world_per_s: math.Quaternion,
    angular_velocity_body_radps2: math.Vec3,

    pub fn isFinite(self: Derivative) bool {
        return self.position_world_mps.isFinite() and
            self.velocity_world_mps2.isFinite() and
            self.body_to_world_per_s.isFinite() and
            self.angular_velocity_body_radps2.isFinite();
    }
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

fn evaluatedDerivative(
    state: State,
    properties: mass_properties.MassProperties,
    callback: LoadCallback,
    time_s: f64,
) IntegrationError!Derivative {
    try state.validate();
    const loads = callback.evaluate(callback.context, time_s, state);
    if (!loads.isFinite()) return error.NonFiniteLoads;
    const result = derivative(state, properties, loads.wrench, loads.gravity_world_mps2);
    if (!result.isFinite()) return error.NonFiniteDerivative;
    return result;
}

pub fn rk4StepCoupled(
    state: State,
    properties: mass_properties.MassProperties,
    callback: LoadCallback,
    time_s: f64,
    dt_s: f64,
) IntegrationError!State {
    if (!(dt_s > 0.0) or !std.math.isFinite(dt_s)) return error.InvalidStep;
    if (!std.math.isFinite(time_s)) return error.NonFiniteTime;
    try state.validate();

    const k1 = try evaluatedDerivative(state, properties, callback, time_s);
    const k2_state = advanced(state, k1, 0.5 * dt_s);
    const k2 = try evaluatedDerivative(k2_state, properties, callback, time_s + 0.5 * dt_s);
    const k3_state = advanced(state, k2, 0.5 * dt_s);
    const k3 = try evaluatedDerivative(k3_state, properties, callback, time_s + 0.5 * dt_s);
    const k4_state = advanced(state, k3, dt_s);
    const k4 = try evaluatedDerivative(k4_state, properties, callback, time_s + dt_s);

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
    if (!weighted.isFinite()) return error.NonFiniteDerivative;

    var result = advanced(state, weighted, one_sixth_dt);
    try result.validate();
    result.body_to_world = result.body_to_world.normalized() catch return error.InvalidOrientation;
    return result;
}

const ConstantLoadsContext = struct {
    loads: Loads,
};

fn evaluateConstantLoads(context: ?*anyopaque, _: f64, _: State) Loads {
    const typed: *ConstantLoadsContext = @ptrCast(@alignCast(context.?));
    return typed.loads;
}

/// Compatibility wrapper. Its wrench and gravity remain constant over the step.
pub fn rk4Step(
    state: State,
    properties: mass_properties.MassProperties,
    wrench: Wrench,
    gravity_world_mps2: math.Vec3,
    dt_s: f64,
) IntegrationError!State {
    var context = ConstantLoadsContext{ .loads = .{
        .wrench = wrench,
        .gravity_world_mps2 = gravity_world_mps2,
    } };
    return rk4StepCoupled(state, properties, .{
        .context = &context,
        .evaluate = evaluateConstantLoads,
    }, 0.0, dt_s);
}

pub fn rk4StepCoupledResult(
    context: evidence.Context,
    state: State,
    properties: mass_properties.MassProperties,
    callback: LoadCallback,
    time_s: f64,
    dt_s: f64,
) IntegrationError!numerical_result.NumericalResult(State) {
    const next = try rk4StepCoupled(state, properties, callback, time_s, dt_s);
    return .{
        .value = next,
        .model = manifest,
        .context = context,
        .validity = .valid,
        .evaluated_point = .{
            .variable = "time_s",
            .value = time_s + dt_s,
            .unit = "s",
        },
        .envelope = manifest.effectiveEnvelope("time_s"),
    };
}

pub fn rk4StepResult(
    context: evidence.Context,
    state: State,
    properties: mass_properties.MassProperties,
    wrench: Wrench,
    gravity_world_mps2: math.Vec3,
    dt_s: f64,
) IntegrationError!numerical_result.NumericalResult(State) {
    const next = try rk4Step(state, properties, wrench, gravity_world_mps2, dt_s);
    return .{
        .value = next,
        .model = manifest,
        .context = context,
        .validity = .valid,
        .evaluated_point = .{ .variable = "time_s", .value = dt_s, .unit = "s" },
        .envelope = manifest.effectiveEnvelope("time_s"),
    };
}

pub const StateErrorEstimate = struct {
    position_m: f64,
    velocity_mps: f64,
    orientation: f64,
    angular_velocity_radps: f64,

    pub fn maxComponent(self: StateErrorEstimate) f64 {
        return @max(@max(self.position_m, self.velocity_mps), @max(self.orientation, self.angular_velocity_radps));
    }
};

pub const EmbeddedStepResult = struct {
    state: State,
    error_estimate: StateErrorEstimate,
    load_evaluations: u8,
};

fn vecDifferenceNorm(a: math.Vec3, b: math.Vec3) f64 {
    return @sqrt(a.sub(b).normSquared());
}

fn quaternionDifferenceNorm(a: math.Quaternion, b: math.Quaternion) f64 {
    const direct = a.add(b.scale(-1.0)).normSquared();
    const antipodal = a.add(b).normSquared();
    return @sqrt(@min(direct, antipodal));
}

/// RK4 step-doubling estimate. The returned state is the two-half-step result;
/// the local truncation estimate is `(two_half - full) / 15`.
pub fn rk4StepCoupledWithErrorEstimate(
    state: State,
    properties: mass_properties.MassProperties,
    callback: LoadCallback,
    time_s: f64,
    dt_s: f64,
) IntegrationError!EmbeddedStepResult {
    const full = try rk4StepCoupled(state, properties, callback, time_s, dt_s);
    const first_half = try rk4StepCoupled(state, properties, callback, time_s, 0.5 * dt_s);
    const second_half = try rk4StepCoupled(first_half, properties, callback, time_s + 0.5 * dt_s, 0.5 * dt_s);
    const divisor = 15.0;
    return .{
        .state = second_half,
        .error_estimate = .{
            .position_m = vecDifferenceNorm(second_half.position_world_m, full.position_world_m) / divisor,
            .velocity_mps = vecDifferenceNorm(second_half.velocity_world_mps, full.velocity_world_mps) / divisor,
            .orientation = quaternionDifferenceNorm(second_half.body_to_world, full.body_to_world) / divisor,
            .angular_velocity_radps = vecDifferenceNorm(
                second_half.angular_velocity_body_radps,
                full.angular_velocity_body_radps,
            ) / divisor,
        },
        .load_evaluations = 12,
    };
}

pub const IntegrationDiagnostics = struct {
    translational_kinetic_energy_j: f64,
    rotational_kinetic_energy_j: f64,
    angular_momentum_body_kg_m2_radps: math.Vec3,
    angular_momentum_world_kg_m2_radps: math.Vec3,
};

pub fn diagnostics(
    state: State,
    properties: mass_properties.MassProperties,
) IntegrationError!IntegrationDiagnostics {
    try state.validate();
    const angular_momentum_body = properties.inertia_kg_m2.multiply(state.angular_velocity_body_radps);
    const angular_momentum_world = state.body_to_world.bodyToWorld(angular_momentum_body) catch
        return error.InvalidOrientation;
    const translational = 0.5 * properties.mass_kg * state.velocity_world_mps.normSquared();
    const rotational = 0.5 * state.angular_velocity_body_radps.dot(angular_momentum_body);
    if (!std.math.isFinite(translational) or !std.math.isFinite(rotational) or
        !angular_momentum_body.isFinite() or !angular_momentum_world.isFinite())
        return error.NonFiniteState;
    return .{
        .translational_kinetic_energy_j = translational,
        .rotational_kinetic_energy_j = rotational,
        .angular_momentum_body_kg_m2_radps = angular_momentum_body,
        .angular_momentum_world_kg_m2_radps = angular_momentum_world,
    };
}

pub fn observedConvergenceOrder(
    coarse_error: f64,
    fine_error: f64,
    refinement_ratio: f64,
) error{InvalidConvergenceSample}!f64 {
    if (!std.math.isFinite(coarse_error) or !std.math.isFinite(fine_error) or
        !std.math.isFinite(refinement_ratio) or !(coarse_error > 0.0) or
        !(fine_error > 0.0) or !(refinement_ratio > 1.0))
        return error.InvalidConvergenceSample;
    return @log(coarse_error / fine_error) / @log(refinement_ratio);
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

const ManufacturedContext = struct {
    evaluations: usize = 0,
};

fn manufacturedVelocityLoad(context: ?*anyopaque, _: f64, state: State) Loads {
    const typed: *ManufacturedContext = @ptrCast(@alignCast(context.?));
    typed.evaluations += 1;
    return .{ .wrench = .{ .force_world_n = .{
        .x = -2.0 * state.velocity_world_mps.x,
        .y = 0.0,
        .z = 0.0,
    } } };
}

fn zeroLoads(_: ?*anyopaque, _: f64, _: State) Loads {
    return .{};
}

fn nonFiniteLoads(_: ?*anyopaque, _: f64, _: State) Loads {
    return .{ .wrench = .{ .force_world_n = .{
        .x = std.math.inf(f64),
        .y = 0.0,
        .z = 0.0,
    } } };
}

fn manufacturedInitial() State {
    return .{
        .position_world_m = math.Vec3.zero,
        .velocity_world_mps = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .body_to_world = math.Quaternion.identity,
        .angular_velocity_body_radps = math.Vec3.zero,
    };
}

test "state-dependent force is reevaluated at every RK4 stage" {
    var context = ManufacturedContext{};
    const dt = 0.2;
    const result = try rk4StepCoupled(
        manufacturedInitial(),
        try testProperties(),
        .{ .context = &context, .evaluate = manufacturedVelocityLoad },
        0.0,
        dt,
    );
    const expected_rk4 = 1.0 - dt + dt * dt / 2.0 - dt * dt * dt / 6.0 +
        dt * dt * dt * dt / 24.0;
    try std.testing.expectEqual(@as(usize, 4), context.evaluations);
    try std.testing.expectApproxEqAbs(expected_rk4, result.velocity_world_mps.x, 1e-14);
}

fn manufacturedError(step_s: f64) !f64 {
    var state = manufacturedInitial();
    var context = ManufacturedContext{};
    const count: usize = @intFromFloat(@round(1.0 / step_s));
    for (0..count) |index| {
        state = try rk4StepCoupled(
            state,
            try testProperties(),
            .{ .context = &context, .evaluate = manufacturedVelocityLoad },
            @as(f64, @floatFromInt(index)) * step_s,
            step_s,
        );
    }
    return @abs(state.velocity_world_mps.x - @exp(-1.0));
}

test "manufactured solution exhibits approximately fourth-order RK convergence" {
    const coarse_error = try manufacturedError(0.1);
    const fine_error = try manufacturedError(0.05);
    const order = try observedConvergenceOrder(coarse_error, fine_error, 2.0);
    try std.testing.expect(order > 3.8 and order < 4.2);
}

test "step doubling supplies a finite embedded error estimate" {
    var context = ManufacturedContext{};
    const result = try rk4StepCoupledWithErrorEstimate(
        manufacturedInitial(),
        try testProperties(),
        .{ .context = &context, .evaluate = manufacturedVelocityLoad },
        0.0,
        0.2,
    );
    try std.testing.expectEqual(@as(u8, 12), result.load_evaluations);
    try std.testing.expectEqual(@as(usize, 12), context.evaluations);
    try std.testing.expect(result.error_estimate.maxComponent() > 0.0);
    try std.testing.expect(std.math.isFinite(result.error_estimate.maxComponent()));
}

test "torque-free asymmetric body conserves energy and world angular momentum trend" {
    const properties = try mass_properties.MassProperties.init(
        1.0,
        math.Vec3.zero,
        .{ .xx = 1.0, .yy = 2.0, .zz = 3.0 },
    );
    var state = State{
        .position_world_m = math.Vec3.zero,
        .velocity_world_mps = math.Vec3.zero,
        .body_to_world = math.Quaternion.identity,
        .angular_velocity_body_radps = .{ .x = 0.7, .y = -0.4, .z = 0.2 },
    };
    const initial = try diagnostics(state, properties);
    const dt = 0.001;
    for (0..2000) |index| {
        state = try rk4StepCoupled(
            state,
            properties,
            .{ .evaluate = zeroLoads },
            @as(f64, @floatFromInt(index)) * dt,
            dt,
        );
    }
    const final = try diagnostics(state, properties);
    const energy_relative_drift = @abs(
        final.rotational_kinetic_energy_j - initial.rotational_kinetic_energy_j,
    ) / initial.rotational_kinetic_energy_j;
    const momentum_relative_drift = vecDifferenceNorm(
        final.angular_momentum_world_kg_m2_radps,
        initial.angular_momentum_world_kg_m2_radps,
    ) / @sqrt(initial.angular_momentum_world_kg_m2_radps.normSquared());
    try std.testing.expect(energy_relative_drift < 1e-10);
    try std.testing.expect(momentum_relative_drift < 1e-10);
}

test "integrator refuses NaN Inf and invalid orientation" {
    var invalid = manufacturedInitial();
    invalid.position_world_m.x = std.math.nan(f64);
    try std.testing.expectError(error.NonFiniteState, rk4StepCoupled(
        invalid,
        try testProperties(),
        .{ .evaluate = zeroLoads },
        0.0,
        0.1,
    ));

    invalid = manufacturedInitial();
    invalid.body_to_world = .{ .w = 0.0, .x = 0.0, .y = 0.0, .z = 0.0 };
    try std.testing.expectError(error.InvalidOrientation, rk4StepCoupled(
        invalid,
        try testProperties(),
        .{ .evaluate = zeroLoads },
        0.0,
        0.1,
    ));

    try std.testing.expectError(error.NonFiniteLoads, rk4StepCoupled(
        manufacturedInitial(),
        try testProperties(),
        .{ .evaluate = nonFiniteLoads },
        0.0,
        0.1,
    ));
    try std.testing.expectError(error.NonFiniteTime, rk4StepCoupled(
        manufacturedInitial(),
        try testProperties(),
        .{ .evaluate = zeroLoads },
        std.math.inf(f64),
        0.1,
    ));
}
