//! Coupled aerodynamic/propulsive force provider for the current rigid-body API.

const std = @import("std");
const types = @import("types.zig");
const airdata = @import("airdata.zig");
const coefficients = @import("coefficients.zig");
const forces = @import("forces.zig");
const propulsion = @import("propulsion.zig");

pub const State = struct {
    velocity_world_mps: types.Vec3,
    body_to_world: types.Quaternion,
    angular_velocity_body_radps: types.Vec3,
};

pub const Wrench = struct {
    force_world_n: types.Vec3 = types.Vec3.zero,
    moment_body_nm: types.Vec3 = types.Vec3.zero,
};

pub const Environment = struct {
    density_kg_m3: f64,
    speed_of_sound_mps: f64,
    temperature_k: f64,
    wind_world_mps: types.Vec3 = types.Vec3.zero,
    height_above_ground_m: ?f64 = null,
};

pub const Command = struct {
    controls: coefficients.Controls = .{},
    throttle: f64 = 0.0,
};

pub const Provider = struct {
    geometry: forces.Geometry,
    aerodynamics: coefficients.Model,
    engine: propulsion.Model,
    minimum_airspeed_mps: f64 = 1.0,
    apply_ground_effect: bool = false,

    pub fn evaluate(
        self: Provider,
        state: State,
        environment: Environment,
        command: Command,
    ) !Evaluation {
        const relative_world = state.velocity_world_mps.sub(environment.wind_world_mps);
        const inverse = state.body_to_world.conjugate();
        const relative_body = inverse.rotate(relative_world);
        const air = try airdata.evaluate(.{
            .velocity_body_mps = relative_body,
            .density_kg_m3 = environment.density_kg_m3,
            .speed_of_sound_mps = environment.speed_of_sound_mps,
            .temperature_k = environment.temperature_k,
            .reference_length_m = self.geometry.chord_m,
            .minimum_speed_mps = self.minimum_airspeed_mps,
        });
        var coefficient = try self.aerodynamics.evaluate(
            air,
            command.controls,
            state.angular_velocity_body_radps,
            self.geometry.span_m,
            self.geometry.chord_m,
        );
        if (self.apply_ground_effect) {
            const height = environment.height_above_ground_m orelse return error.MissingGroundHeight;
            const factor = try groundEffectLiftFactor(height, self.geometry.span_m);
            coefficient.cz *= factor;
        }
        var body_wrench = try forces.reconstruct(coefficient, air.dynamic_pressure_pa, self.geometry);
        const engine_output = try self.engine.evaluate(command.throttle, air.speed_mps);
        body_wrench.force_n.x += engine_output.thrust_n;
        return .{
            .wrench = .{
                .force_world_n = state.body_to_world.rotate(body_wrench.force_n),
                .moment_body_nm = body_wrench.moment_nm,
            },
            .airdata = air,
            .coefficient = coefficient,
            .fuel_flow_kgps = engine_output.fuel_flow_kgps,
        };
    }
};

pub const Evaluation = struct {
    wrench: Wrench,
    airdata: airdata.State,
    coefficient: coefficients.Six,
    fuel_flow_kgps: f64,
};

/// Copies the fields used by this lane from the current dynamics State. This
/// remains generic so the fixed-wing lane can compile before package-root wiring.
pub fn fromDynamicsState(state: anytype) State {
    return .{
        .velocity_world_mps = .{
            .x = state.velocity_world_mps.x,
            .y = state.velocity_world_mps.y,
            .z = state.velocity_world_mps.z,
        },
        .body_to_world = .{
            .w = state.body_to_world.w,
            .x = state.body_to_world.x,
            .y = state.body_to_world.y,
            .z = state.body_to_world.z,
        },
        .angular_velocity_body_radps = .{
            .x = state.angular_velocity_body_radps.x,
            .y = state.angular_velocity_body_radps.y,
            .z = state.angular_velocity_body_radps.z,
        },
    };
}

/// Copies an evaluation into a `dynamics.rigid_body.Wrench`-shaped pointer
/// without importing across this lane's temporary package boundary.
pub fn writeDynamicsWrench(evaluation: Evaluation, destination: anytype) void {
    destination.force_world_n.x = evaluation.wrench.force_world_n.x;
    destination.force_world_n.y = evaluation.wrench.force_world_n.y;
    destination.force_world_n.z = evaluation.wrench.force_world_n.z;
    destination.moment_body_nm.x = evaluation.wrench.moment_body_nm.x;
    destination.moment_body_nm.y = evaluation.wrench.moment_body_nm.y;
    destination.moment_body_nm.z = evaluation.wrench.moment_body_nm.z;
}

fn groundEffectLiftFactor(height_above_ground_m: f64, span_m: f64) !f64 {
    if (!std.math.isFinite(height_above_ground_m) or !std.math.isFinite(span_m) or !(span_m > 0.0))
        return error.InvalidGroundGeometry;
    if (height_above_ground_m < 0.0) return error.BelowGround;
    const ratio = height_above_ground_m / span_m;
    return if (ratio >= 1.0) 1.0 else 1.0 + 0.25 * (1.0 - ratio);
}

test "coupled provider evaluation is finite and repeatable near convergence" {
    const alpha_axis = [_]f64{ -0.3, 0.3 };
    const beta_axis = [_]f64{ -0.2, 0.2 };
    const mach_axis = [_]f64{ 0.0, 0.5 };
    var values: [8]coefficients.Six = undefined;
    var i: usize = 0;
    for (alpha_axis) |a| for (beta_axis) |b| for (mach_axis) |_| {
        values[i] = .{ .cx = -0.04, .cy = -b, .cz = -4.0 * a, .cm = -0.5 * a };
        i += 1;
    };
    const provider = Provider{
        .geometry = .{ .area_m2 = 1.0, .span_m = 2.0, .chord_m = 0.5 },
        .aerodynamics = .{ .grid = .{
            .alpha_rad = &alpha_axis,
            .beta_rad = &beta_axis,
            .mach = &mach_axis,
            .values = &values,
        } },
        .engine = .{
            .static_thrust_n = 100.0,
            .zero_thrust_speed_mps = 100.0,
            .full_fuel_kgps = 0.01,
        },
    };
    const state = State{
        .velocity_world_mps = .{ .x = 30.0, .y = 0.0, .z = 1e-7 },
        .body_to_world = types.Quaternion.identity,
        .angular_velocity_body_radps = types.Vec3.zero,
    };
    const env = Environment{
        .density_kg_m3 = 1.225,
        .speed_of_sound_mps = 340.0,
        .temperature_k = 288.15,
    };
    const a = try provider.evaluate(state, env, .{ .throttle = 0.2 });
    const b = try provider.evaluate(state, env, .{ .throttle = 0.2 });
    try std.testing.expect(a.wrench.force_world_n.isFinite());
    try std.testing.expectApproxEqAbs(a.wrench.force_world_n.x, b.wrench.force_world_n.x, 0.0);
    var dynamics_wrench = Wrench{};
    writeDynamicsWrench(a, &dynamics_wrench);
    try std.testing.expectApproxEqAbs(a.wrench.force_world_n.x, dynamics_wrench.force_world_n.x, 0.0);
}
