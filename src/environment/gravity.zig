//! Bounded local gravity models. Coordinates are local z-up. These are normal
//! gravity approximations; terrain and local mass anomalies are not modeled.

const std = @import("std");
const math = @import("../dynamics/math.zig");

pub const standard_gravity_mps2 = 9.80665;
pub const earth_mean_radius_m = 6_371_008.8;
pub const max_supported_altitude_m = 100_000.0;
pub const equatorial_normal_gravity_mps2 = 9.7803253359;
pub const somigliana_k = 0.00193185265241;
pub const first_eccentricity_squared = 0.00669437999013;

pub const Evaluation = union(enum) {
    valid: math.Vec3,
    outside_envelope,
};

/// Inverse-square magnitude referenced to standard gravity at mean Earth
/// radius. Valid only for geometric altitude from 0 through 100 km.
pub fn inverseSquareZUp(altitude_m: f64) Evaluation {
    if (!std.math.isFinite(altitude_m) or altitude_m < 0.0 or altitude_m > max_supported_altitude_m) {
        return .outside_envelope;
    }
    const ratio = earth_mean_radius_m / (earth_mean_radius_m + altitude_m);
    return .{ .valid = .{ .x = 0.0, .y = 0.0, .z = -standard_gravity_mps2 * ratio * ratio } };
}

/// Somigliana normal gravity on the WGS84 ellipsoid, continued with a bounded
/// inverse-square height correction from 0 through 100 km.
pub fn latitudeHeightZUp(latitude_rad: f64, height_m: f64) Evaluation {
    if (!std.math.isFinite(latitude_rad) or !std.math.isFinite(height_m) or
        @abs(latitude_rad) > std.math.pi / 2.0 or
        height_m < 0.0 or height_m > max_supported_altitude_m)
        return .outside_envelope;
    const sin_lat = @sin(latitude_rad);
    const sin_squared = sin_lat * sin_lat;
    const surface = equatorial_normal_gravity_mps2 *
        (1.0 + somigliana_k * sin_squared) /
        @sqrt(1.0 - first_eccentricity_squared * sin_squared);
    const height_ratio = earth_mean_radius_m / (earth_mean_radius_m + height_m);
    return .{ .valid = .{
        .x = 0.0,
        .y = 0.0,
        .z = -surface * height_ratio * height_ratio,
    } };
}

test "sea-level gravity is standard gravity and points down" {
    const acceleration = inverseSquareZUp(0.0).valid;
    try std.testing.expectApproxEqAbs(@as(f64, -standard_gravity_mps2), acceleration.z, 1e-14);
    try std.testing.expectEqual(@as(f64, 0.0), acceleration.x);
    try std.testing.expectEqual(@as(f64, 0.0), acceleration.y);
}

test "gravity weakens with altitude and refuses unsupported altitude" {
    const sea_level = inverseSquareZUp(0.0).valid;
    const high = inverseSquareZUp(100_000.0).valid;
    try std.testing.expect(@abs(high.z) < @abs(sea_level.z));
    try std.testing.expect(inverseSquareZUp(-1.0) == .outside_envelope);
    try std.testing.expect(inverseSquareZUp(100_001.0) == .outside_envelope);
}

test "normal gravity varies with latitude and height" {
    const equator = latitudeHeightZUp(0.0, 0.0).valid;
    const pole = latitudeHeightZUp(std.math.pi / 2.0, 0.0).valid;
    const high = latitudeHeightZUp(std.math.pi / 2.0, 100_000.0).valid;
    try std.testing.expect(@abs(pole.z) > @abs(equator.z));
    try std.testing.expect(@abs(high.z) < @abs(pole.z));
}

test "latitude-height gravity refuses NaN Inf and invalid latitude" {
    try std.testing.expect(latitudeHeightZUp(std.math.nan(f64), 0.0) == .outside_envelope);
    try std.testing.expect(latitudeHeightZUp(0.0, std.math.inf(f64)) == .outside_envelope);
    try std.testing.expect(latitudeHeightZUp(std.math.pi, 0.0) == .outside_envelope);
}
