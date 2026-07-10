//! Bounded fixed-wing air-data reconstruction.
//! Body axes are x-forward, y-right, z-down. Relative air velocity is the
//! aircraft velocity relative to the air mass, expressed in body axes.

const std = @import("std");
const Vec3 = @import("types.zig").Vec3;

pub const Error = error{
    NonFiniteInput,
    InvalidAtmosphere,
    InvalidReferenceLength,
    LowSpeed,
};

pub const State = struct {
    velocity_body_mps: Vec3,
    speed_mps: f64,
    dynamic_pressure_pa: f64,
    alpha_rad: f64,
    beta_rad: f64,
    mach: f64,
    reynolds: f64,
};

pub const Inputs = struct {
    velocity_body_mps: Vec3,
    density_kg_m3: f64,
    speed_of_sound_mps: f64,
    temperature_k: f64,
    reference_length_m: f64,
    minimum_speed_mps: f64 = 1.0,
};

/// Dynamic viscosity from Sutherland's law for dry air.
pub fn dynamicViscosity(temperature_k: f64) Error!f64 {
    if (!std.math.isFinite(temperature_k) or !(temperature_k > 0.0)) return error.InvalidAtmosphere;
    const reference_temperature_k = 273.15;
    const reference_viscosity_pa_s = 1.716e-5;
    const sutherland_k = 110.4;
    return reference_viscosity_pa_s *
        std.math.pow(f64, temperature_k / reference_temperature_k, 1.5) *
        (reference_temperature_k + sutherland_k) / (temperature_k + sutherland_k);
}

pub fn evaluate(input: Inputs) Error!State {
    if (!input.velocity_body_mps.isFinite() or
        !std.math.isFinite(input.minimum_speed_mps) or !(input.minimum_speed_mps > 0.0))
        return error.NonFiniteInput;
    if (!std.math.isFinite(input.density_kg_m3) or !(input.density_kg_m3 > 0.0) or
        !std.math.isFinite(input.speed_of_sound_mps) or !(input.speed_of_sound_mps > 0.0))
        return error.InvalidAtmosphere;
    if (!std.math.isFinite(input.reference_length_m) or !(input.reference_length_m > 0.0))
        return error.InvalidReferenceLength;

    const speed = @sqrt(input.velocity_body_mps.normSquared());
    if (!std.math.isFinite(speed) or speed < input.minimum_speed_mps) return error.LowSpeed;
    const viscosity = try dynamicViscosity(input.temperature_k);
    const side_ratio = std.math.clamp(input.velocity_body_mps.y / speed, -1.0, 1.0);
    return .{
        .velocity_body_mps = input.velocity_body_mps,
        .speed_mps = speed,
        .dynamic_pressure_pa = 0.5 * input.density_kg_m3 * speed * speed,
        .alpha_rad = std.math.atan2(input.velocity_body_mps.z, input.velocity_body_mps.x),
        .beta_rad = std.math.asin(side_ratio),
        .mach = speed / input.speed_of_sound_mps,
        .reynolds = input.density_kg_m3 * speed * input.reference_length_m / viscosity,
    };
}

test "airdata signs and symmetry follow body convention" {
    const common = Inputs{
        .velocity_body_mps = .{ .x = 50.0, .y = 4.0, .z = 5.0 },
        .density_kg_m3 = 1.225,
        .speed_of_sound_mps = 340.0,
        .temperature_k = 288.15,
        .reference_length_m = 1.0,
    };
    const positive = try evaluate(common);
    var mirrored = common;
    mirrored.velocity_body_mps.y = -common.velocity_body_mps.y;
    const negative = try evaluate(mirrored);
    try std.testing.expect(positive.alpha_rad > 0.0);
    try std.testing.expect(positive.beta_rad > 0.0);
    try std.testing.expectApproxEqAbs(-positive.beta_rad, negative.beta_rad, 1e-14);
    try std.testing.expect(positive.mach > 0.0 and positive.reynolds > 1.0);
}

test "airdata refuses low speed" {
    try std.testing.expectError(error.LowSpeed, evaluate(.{
        .velocity_body_mps = .{ .x = 0.2, .y = 0.0, .z = 0.0 },
        .density_kg_m3 = 1.225,
        .speed_of_sound_mps = 340.0,
        .temperature_k = 288.15,
        .reference_length_m = 1.0,
        .minimum_speed_mps = 1.0,
    }));
}
