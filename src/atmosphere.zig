//! 1976 U.S. Standard Atmosphere, troposphere segment only.

const std = @import("std");
const evidence = @import("evidence.zig");
const units = @import("units.zig");

pub const min_altitude_m = 0.0;
pub const max_altitude_m = 11_000.0;

const sea_level_temperature_k = 288.15;
const sea_level_pressure_pa = 101_325.0;
const lapse_rate_k_per_m = 0.0065;
const standard_gravity_mps2 = 9.80665;
const specific_gas_constant_air = 287.05287;
const heat_capacity_ratio_air = 1.4;

const assumptions = [_][]const u8{
    "dry ideal gas",
    "constant tropospheric lapse rate",
    "geopotential altitude from 0 m through 11000 m",
};

pub const manifest = evidence.ModelManifest{
    .id = "strip.atmosphere.us76-troposphere",
    .version = "0.1.0",
    .proof_level = .analytical,
    .source = "U.S. Standard Atmosphere, 1976; troposphere equations",
    .assumptions = &assumptions,
    .valid_min = min_altitude_m,
    .valid_max = max_altitude_m,
    .valid_unit = "m_geopotential",
};

pub const State = struct {
    temperature: units.Temperature,
    pressure: units.Pressure,
    density: units.Density,
    speed_of_sound: units.Speed,
};

pub const Evaluation = struct {
    altitude: units.GeopotentialAltitude,
    validity: evidence.ValidityStatus,
    state: ?State,
};

pub fn evaluate(altitude: units.GeopotentialAltitude) Evaluation {
    if (altitude.meters < min_altitude_m or altitude.meters > max_altitude_m) {
        return .{
            .altitude = altitude,
            .validity = .outside_envelope,
            .state = null,
        };
    }

    const temperature = sea_level_temperature_k - lapse_rate_k_per_m * altitude.meters;
    const exponent = standard_gravity_mps2 / (specific_gas_constant_air * lapse_rate_k_per_m);
    const pressure = sea_level_pressure_pa * std.math.pow(f64, temperature / sea_level_temperature_k, exponent);
    const density = pressure / (specific_gas_constant_air * temperature);
    const speed_of_sound = @sqrt(heat_capacity_ratio_air * specific_gas_constant_air * temperature);

    return .{
        .altitude = altitude,
        .validity = .valid,
        .state = .{
            .temperature = .{ .kelvin = temperature },
            .pressure = .{ .pascals = pressure },
            .density = .{ .kilograms_per_cubic_meter = density },
            .speed_of_sound = .{ .meters_per_second = speed_of_sound },
        },
    };
}

test "sea-level state matches standard reference values" {
    const result = evaluate(try units.GeopotentialAltitude.init(0.0));
    const state = result.state.?;
    try std.testing.expectEqual(evidence.ValidityStatus.valid, result.validity);
    try std.testing.expectApproxEqAbs(@as(f64, 288.15), state.temperature.kelvin, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 101_325.0), state.pressure.pascals, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 1.225), state.density.kilograms_per_cubic_meter, 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 340.294), state.speed_of_sound.meters_per_second, 1e-3);
}

test "troposphere ceiling matches standard pressure" {
    const result = evaluate(try units.GeopotentialAltitude.init(11_000.0));
    try std.testing.expectApproxEqAbs(@as(f64, 22_632.0), result.state.?.pressure.pascals, 1.0);
}

test "outside-envelope requests carry no numerical state" {
    const result = evaluate(try units.GeopotentialAltitude.init(11_001.0));
    try std.testing.expectEqual(evidence.ValidityStatus.outside_envelope, result.validity);
    try std.testing.expect(result.state == null);
}
