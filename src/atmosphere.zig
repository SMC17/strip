//! Authoritative U.S. Standard Atmosphere (1976) public API.
//!
//! Implementation delegates to `weather.atmosphere` (layered 0–86 km geopotential).
//! `Model.us76_troposphere` is a validity envelope variant for legacy troposphere-only
//! consumers; there is no second numerical implementation.

const std = @import("std");
const evidence = @import("evidence.zig");
const result = @import("result.zig");
const units = @import("units.zig");
const weather_atmos = @import("weather/root.zig").atmosphere;

pub const Model = enum {
    us76_layered,
    us76_troposphere,
};

pub const min_altitude_m = weather_atmos.min_geopotential_altitude_m;
pub const max_altitude_m_layered = weather_atmos.max_geopotential_altitude_m;
pub const max_altitude_m_troposphere = 11_000.0;

const assumptions = [_][]const u8{
    "dry ideal gas",
    "hydrostatic layered US76 through 86 km geopotential",
    "homogeneous composition below mesopause envelope",
};

const troposphere_assumptions = [_][]const u8{
    "dry ideal gas",
    "constant tropospheric lapse rate",
    "geopotential altitude from 0 m through 11000 m",
};

pub const manifest_layered = evidence.ModelManifest{
    .id = "strip.atmosphere.us76-layered",
    .version = "0.2.0",
    .proof_level = .analytical,
    .source = "U.S. Standard Atmosphere, 1976; layered hydrostatic equations",
    .assumptions = &assumptions,
    .valid_min = min_altitude_m,
    .valid_max = max_altitude_m_layered,
    .valid_unit = "m_geopotential",
};

pub const manifest_troposphere = evidence.ModelManifest{
    .id = "strip.atmosphere.us76-troposphere",
    .version = "0.2.0",
    .proof_level = .analytical,
    .source = "U.S. Standard Atmosphere, 1976; troposphere envelope variant",
    .assumptions = &troposphere_assumptions,
    .valid_min = min_altitude_m,
    .valid_max = max_altitude_m_troposphere,
    .valid_unit = "m_geopotential",
};

/// Default manifest: full layered US76 (authoritative).
pub const manifest = manifest_layered;

pub fn manifestFor(model: Model) evidence.ModelManifest {
    return switch (model) {
        .us76_layered => manifest_layered,
        .us76_troposphere => manifest_troposphere,
    };
}

pub fn maxAltitudeFor(model: Model) f64 {
    return switch (model) {
        .us76_layered => max_altitude_m_layered,
        .us76_troposphere => max_altitude_m_troposphere,
    };
}

pub const State = result.AtmosphereState;

/// Backward-compatible alias.
pub const Evaluation = result.AtmosphereEvaluation;

pub fn evaluate(altitude: units.GeopotentialAltitude) Evaluation {
    return evaluateWithModel(.us76_layered, altitude);
}

pub fn evaluateWithModel(model: Model, altitude: units.GeopotentialAltitude) Evaluation {
    const model_manifest = manifestFor(model);
    const envelope = model_manifest.effectiveEnvelope("geopotential_altitude_m");
    const h = altitude.meters;
    if (h < envelope.minimum or h > envelope.maximum) {
        return .{
            .altitude = altitude,
            .validity = .outside_envelope,
            .state = null,
            .model = model_manifest,
            .envelope = envelope,
        };
    }

    const raw = weather_atmos.evaluate(h) catch {
        return .{
            .altitude = altitude,
            .validity = .invalid_input,
            .state = null,
            .model = model_manifest,
            .envelope = envelope,
        };
    };

    return .{
        .altitude = altitude,
        .validity = .valid,
        .state = .{
            .temperature = .{ .kelvin = raw.temperature_k },
            .pressure = .{ .pascals = raw.pressure_pa },
            .density = .{ .kilograms_per_cubic_meter = raw.density_kg_m3 },
            .speed_of_sound = .{ .meters_per_second = raw.speed_of_sound_mps },
            .layer_index = raw.layer_index,
        },
        .model = model_manifest,
        .envelope = envelope,
    };
}

pub fn evaluateResult(
    context: evidence.Context,
    altitude: units.GeopotentialAltitude,
) !result.NumericalResult(?State) {
    const evaluation = evaluate(altitude);
    return .{
        .value = evaluation.state,
        .model = evaluation.model,
        .context = context,
        .validity = evaluation.validity,
        .evaluated_point = .{
            .variable = "geopotential_altitude_m",
            .value = altitude.meters,
            .unit = "m",
        },
        .envelope = evaluation.envelope,
    };
}

test "sea-level state matches standard reference values" {
    const result_eval = evaluate(try units.GeopotentialAltitude.init(0.0));
    const state = result_eval.state.?;
    try std.testing.expectEqual(evidence.ValidityStatus.valid, result_eval.validity);
    try std.testing.expectApproxEqAbs(@as(f64, 288.15), state.temperature.kelvin, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 101_325.0), state.pressure.pascals, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 1.225), state.density.kilograms_per_cubic_meter, 5e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 340.294), state.speed_of_sound.meters_per_second, 1e-3);
}

test "layered atmosphere covers 12 km inside envelope" {
    const result_eval = evaluate(try units.GeopotentialAltitude.init(12_000.0));
    try std.testing.expectEqual(evidence.ValidityStatus.valid, result_eval.validity);
    try std.testing.expect(result_eval.state != null);
}

test "troposphere variant rejects 12 km" {
    const result_eval = evaluateWithModel(.us76_troposphere, try units.GeopotentialAltitude.init(12_000.0));
    try std.testing.expectEqual(evidence.ValidityStatus.outside_envelope, result_eval.validity);
    try std.testing.expect(result_eval.state == null);
}

test "troposphere ceiling matches standard pressure" {
    const result_eval = evaluateWithModel(.us76_troposphere, try units.GeopotentialAltitude.init(11_000.0));
    try std.testing.expectApproxEqAbs(@as(f64, 22_632.06), result_eval.state.?.pressure.pascals, 1.0);
}

test "outside-envelope requests carry no numerical state" {
    const result_eval = evaluate(try units.GeopotentialAltitude.init(max_altitude_m_layered + 1.0));
    try std.testing.expectEqual(evidence.ValidityStatus.outside_envelope, result_eval.validity);
    try std.testing.expect(result_eval.state == null);
}

test "numerical result carries model and envelope metadata" {
    const context = try evidence.Context.init(.research);
    const numerical = try evaluateResult(context, try units.GeopotentialAltitude.init(5000.0));
    try std.testing.expect(numerical.isAuthoritative());
    try std.testing.expectEqualStrings("strip.atmosphere.us76-layered", numerical.model.id);
}
