//! Bounded static-coefficient rotor, motor, and body-wrench primitives.
//! Body axes are x-forward, y-right, z-down. Positive thrust is along -body-z.

const std = @import("std");
const math = @import("math.zig");
const evidence = @import("../evidence.zig");
const numerical_result = @import("../result.zig");

pub const max_rotors = 8;

pub const manifest = evidence.ModelManifest{
    .id = "strip.multirotor.rotor-static-coefficient",
    .version = "0.1.0",
    .proof_level = .unit_tested,
    .source = "Static CT/CP rotor model; UIUC points are validation inputs only",
    .assumptions = &.{
        "static thrust/torque coefficients",
        "no blade-element dynamics",
        "density and omega within caller envelope",
    },
    .valid_min = 0.5,
    .valid_max = 1.5,
    .valid_unit = "kg/m^3",
    .proof = .{
        .implementation = .implemented,
        .testing = .unit_tested,
        .analysis = .none,
        .comparison = .public_benchmark,
        .validation = .experimental,
    },
};

pub const Direction = enum(i8) {
    clockwise = -1,
    counter_clockwise = 1,

    pub fn sign(self: Direction) f64 {
        return @floatFromInt(@intFromEnum(self));
    }
};

pub const CoefficientModel = struct {
    diameter_m: f64,
    thrust_coefficient: f64,
    torque_coefficient: f64,
    max_omega_radps: f64,

    pub fn validate(self: CoefficientModel) error{InvalidModel}!void {
        const values = [_]f64{
            self.diameter_m,
            self.thrust_coefficient,
            self.torque_coefficient,
            self.max_omega_radps,
        };
        for (values) |value| if (!std.math.isFinite(value)) return error.InvalidModel;
        if (!(self.diameter_m > 0.0) or self.thrust_coefficient < 0.0 or
            self.torque_coefficient < 0.0 or !(self.max_omega_radps > 0.0))
            return error.InvalidModel;
    }

    pub fn evaluate(self: CoefficientModel, density_kgpm3: f64, omega_radps_raw: f64) error{InvalidInput}!RotorOutput {
        if (!(density_kgpm3 > 0.0) or !std.math.isFinite(density_kgpm3) or
            !std.math.isFinite(omega_radps_raw))
            return error.InvalidInput;
        const omega = std.math.clamp(omega_radps_raw, 0.0, self.max_omega_radps);
        const revolutions_per_s = omega / (2.0 * std.math.pi);
        const n2 = revolutions_per_s * revolutions_per_s;
        const d2 = self.diameter_m * self.diameter_m;
        const d4 = d2 * d2;
        return .{
            .thrust_n = self.thrust_coefficient * density_kgpm3 * n2 * d4,
            .reaction_torque_nm = self.torque_coefficient * density_kgpm3 * n2 * d4 * self.diameter_m,
            .omega_radps = omega,
        };
    }

    pub fn evaluateResult(
        self: CoefficientModel,
        context: evidence.Context,
        density_kgpm3: f64,
        omega_radps_raw: f64,
    ) error{InvalidInput}!numerical_result.NumericalResult(?RotorOutput) {
        const envelope = manifest.effectiveEnvelope("density_kg_m3");
        if (!envelope.contains(density_kgpm3)) {
            return .{
                .value = null,
                .model = manifest,
                .context = context,
                .validity = .outside_envelope,
                .evaluated_point = .{
                    .variable = "density_kg_m3",
                    .value = density_kgpm3,
                    .unit = "kg/m^3",
                },
                .envelope = envelope,
                .execution_identity = .fromModel(manifest),
                .credibility = .fromProof(manifest.effectiveProof()),
            };
        }
        const output = try self.evaluate(density_kgpm3, omega_radps_raw);
        return .{
            .value = output,
            .model = manifest,
            .context = context,
            .validity = .valid,
            .evaluated_point = .{
                .variable = "density_kg_m3",
                .value = density_kgpm3,
                .unit = "kg/m^3",
            },
            .envelope = envelope,
            .execution_identity = .fromModel(manifest),
            .credibility = .fromProof(manifest.effectiveProof()),
        };
    }

    pub fn maxThrust(self: CoefficientModel, density_kgpm3: f64) error{InvalidInput}!f64 {
        return (try self.evaluate(density_kgpm3, self.max_omega_radps)).thrust_n;
    }
};

pub const RotorOutput = struct {
    thrust_n: f64,
    reaction_torque_nm: f64,
    omega_radps: f64,
};

pub const Motor = struct {
    time_constant_s: f64,
    omega_radps: f64 = 0.0,
    enabled: bool = true,

    pub fn init(time_constant_s: f64, initial_omega_radps: f64) error{InvalidMotor}!Motor {
        if (!(time_constant_s > 0.0) or !std.math.isFinite(time_constant_s) or
            initial_omega_radps < 0.0 or !std.math.isFinite(initial_omega_radps))
            return error.InvalidMotor;
        return .{ .time_constant_s = time_constant_s, .omega_radps = initial_omega_radps };
    }

    /// Exact zero-order-hold update of d(omega)/dt=(target-omega)/tau.
    pub fn step(self: *Motor, command_fraction_raw: f64, max_omega_radps: f64, dt_s: f64) error{InvalidStep}!f64 {
        if (!std.math.isFinite(command_fraction_raw) or !(max_omega_radps > 0.0) or
            !std.math.isFinite(max_omega_radps) or !(dt_s > 0.0) or !std.math.isFinite(dt_s))
            return error.InvalidStep;
        const command = if (self.enabled) std.math.clamp(command_fraction_raw, 0.0, 1.0) else 0.0;
        const target = command * max_omega_radps;
        const alpha = 1.0 - @exp(-dt_s / self.time_constant_s);
        self.omega_radps = std.math.clamp(
            self.omega_radps + alpha * (target - self.omega_radps),
            0.0,
            max_omega_radps,
        );
        return self.omega_radps;
    }
};

/// The lag state represents the combined command-to-speed motor/ESC response.
pub const MotorEsc = Motor;

pub const Rotor = struct {
    position_body_m: math.Vec3,
    direction: Direction,
    model: CoefficientModel,
    motor: Motor,

    pub fn validate(self: Rotor) error{InvalidRotor}!void {
        if (!self.position_body_m.isFinite()) return error.InvalidRotor;
        self.model.validate() catch return error.InvalidRotor;
        if (!(self.motor.time_constant_s > 0.0) or !std.math.isFinite(self.motor.time_constant_s))
            return error.InvalidRotor;
    }

    pub fn step(self: *Rotor, command_fraction: f64, density_kgpm3: f64, dt_s: f64) !RotorOutput {
        const omega = try self.motor.step(command_fraction, self.model.max_omega_radps, dt_s);
        return self.model.evaluate(density_kgpm3, omega);
    }

    pub fn wrench(self: Rotor, output: RotorOutput, ground_effect_factor: f64) Wrench {
        const factor = std.math.clamp(ground_effect_factor, 1.0, 4.0);
        const force = math.Vec3{ .x = 0.0, .y = 0.0, .z = -output.thrust_n * factor };
        const arm_moment = self.position_body_m.cross(force);
        return .{
            .force_body_n = force,
            .moment_body_nm = arm_moment.add(.{
                .x = 0.0,
                .y = 0.0,
                .z = self.direction.sign() * output.reaction_torque_nm,
            }),
        };
    }
};

pub const Wrench = struct {
    force_body_n: math.Vec3 = math.Vec3.zero,
    moment_body_nm: math.Vec3 = math.Vec3.zero,

    pub fn add(a: Wrench, b: Wrench) Wrench {
        return .{
            .force_body_n = a.force_body_n.add(b.force_body_n),
            .moment_body_nm = a.moment_body_nm.add(b.moment_body_nm),
        };
    }
};

pub const WorldWrench = struct {
    force_world_n: math.Vec3,
    moment_body_nm: math.Vec3,
};

pub fn toWorld(body_to_world: math.Quaternion, body_wrench: Wrench) WorldWrench {
    return .{
        .force_world_n = body_to_world.rotate(body_wrench.force_body_n),
        .moment_body_nm = body_wrench.moment_body_nm,
    };
}

pub const DragConfig = struct {
    coefficient_n_per_mps2: math.Vec3,
    maximum_force_n: math.Vec3,

    pub fn force(self: DragConfig, velocity_body_mps: math.Vec3) math.Vec3 {
        return .{
            .x = dragAxis(velocity_body_mps.x, self.coefficient_n_per_mps2.x, self.maximum_force_n.x),
            .y = dragAxis(velocity_body_mps.y, self.coefficient_n_per_mps2.y, self.maximum_force_n.y),
            .z = dragAxis(velocity_body_mps.z, self.coefficient_n_per_mps2.z, self.maximum_force_n.z),
        };
    }
};

fn dragAxis(velocity: f64, coefficient: f64, maximum: f64) f64 {
    if (!std.math.isFinite(velocity) or !std.math.isFinite(coefficient) or
        !std.math.isFinite(maximum) or coefficient < 0.0 or maximum < 0.0)
        return 0.0;
    return std.math.clamp(-coefficient * velocity * @abs(velocity), -maximum, maximum);
}

pub const GroundEffect = struct {
    rotor_radius_m: f64,
    gain: f64,
    maximum_factor: f64,
    minimum_height_m: f64,

    /// Bounded empirical shape only; it is not an identified inflow model.
    pub fn factor(self: GroundEffect, height_above_ground_m: f64) f64 {
        if (!(self.rotor_radius_m > 0.0) or self.gain < 0.0 or self.maximum_factor < 1.0 or
            !(self.minimum_height_m > 0.0) or !std.math.isFinite(height_above_ground_m))
            return 1.0;
        const height = @max(height_above_ground_m, self.minimum_height_m);
        const ratio = self.rotor_radius_m / height;
        return std.math.clamp(1.0 + self.gain * ratio * ratio, 1.0, self.maximum_factor);
    }
};

test "coefficient model, motor lag, and reaction torque are bounded" {
    const model = CoefficientModel{
        .diameter_m = 0.25,
        .thrust_coefficient = 0.1,
        .torque_coefficient = 0.01,
        .max_omega_radps = 600.0,
    };
    var motor = try Motor.init(0.2, 0.0);
    const first = try motor.step(1.0, model.max_omega_radps, 0.2);
    try std.testing.expectApproxEqAbs(600.0 * (1.0 - @exp(-1.0)), first, 1e-12);
    const output = try model.evaluate(1.2, first);
    try std.testing.expect(output.thrust_n > 0.0);
    try std.testing.expect(output.reaction_torque_nm > 0.0);
    motor.enabled = false;
    try std.testing.expect((try motor.step(1.0, model.max_omega_radps, 0.2)) < first);
}

test "attitude rotates thrust and drag opposes velocity" {
    const half = std.math.pi / 4.0;
    const q = math.Quaternion{ .w = @cos(half), .x = 0.0, .y = @sin(half), .z = 0.0 };
    const world = toWorld(q, .{ .force_body_n = .{ .x = 0.0, .y = 0.0, .z = -10.0 } });
    try std.testing.expectApproxEqAbs(@as(f64, -10.0), world.force_world_n.x, 1e-12);
    const drag = (DragConfig{
        .coefficient_n_per_mps2 = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .maximum_force_n = .{ .x = 3.0, .y = 3.0, .z = 3.0 },
    }).force(.{ .x = 2.0, .y = -1.0, .z = 0.0 });
    try std.testing.expectEqual(@as(f64, -3.0), drag.x);
    try std.testing.expectEqual(@as(f64, 1.0), drag.y);
}

test "placement direction and ground effect produce bounded wrench signs" {
    const model = CoefficientModel{
        .diameter_m = 0.25,
        .thrust_coefficient = 0.1,
        .torque_coefficient = 0.01,
        .max_omega_radps = 600.0,
    };
    const rotor = Rotor{
        .position_body_m = .{ .x = 0.2, .y = -0.3, .z = 0.0 },
        .direction = .counter_clockwise,
        .model = model,
        .motor = try Motor.init(0.1, 0.0),
    };
    const output = try model.evaluate(1.2, 300.0);
    const effect = GroundEffect{
        .rotor_radius_m = 0.125,
        .gain = 1.0,
        .maximum_factor = 1.5,
        .minimum_height_m = 0.02,
    };
    try std.testing.expectEqual(@as(f64, 1.5), effect.factor(0.0));
    try std.testing.expect(effect.factor(100.0) >= 1.0);
    const wrench = rotor.wrench(output, effect.factor(0.0));
    try std.testing.expect(wrench.force_body_n.z < 0.0);
    try std.testing.expect(wrench.moment_body_nm.x > 0.0);
    try std.testing.expect(wrench.moment_body_nm.y > 0.0);
    try std.testing.expect(wrench.moment_body_nm.z > 0.0);
}

test "rotor evaluateResult carries credibility vector" {
    const model = CoefficientModel{
        .diameter_m = 0.25,
        .thrust_coefficient = 0.1,
        .torque_coefficient = 0.01,
        .max_omega_radps = 600.0,
    };
    const context = try evidence.Context.init(.preliminary_design);
    const numbered = try model.evaluateResult(context, 1.225, 300.0);
    try std.testing.expect(numbered.isAuthoritative());
    try std.testing.expect(numbered.value != null);
    try std.testing.expect(numbered.credibility.review >= 2);
}
