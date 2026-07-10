//! Earth rotation and local-level transport-rate primitives.

const std = @import("std");
const math = @import("../dynamics/math.zig");

pub const rotation_rate_radps = 7.2921150e-5;
pub const semi_major_axis_m = 6_378_137.0;
pub const first_eccentricity_squared = 6.69437999014e-3;

pub const Error = error{
    NonFiniteInput,
    InvalidLatitude,
    InvalidHeight,
};

fn validateLatitudeHeight(latitude_rad: f64, height_m: f64) Error!void {
    if (!std.math.isFinite(latitude_rad) or !std.math.isFinite(height_m))
        return error.NonFiniteInput;
    if (@abs(latitude_rad) > std.math.pi / 2.0) return error.InvalidLatitude;
    if (height_m <= -semi_major_axis_m) return error.InvalidHeight;
}

pub fn rotationVectorEcef() math.Vec3 {
    return .{ .x = 0.0, .y = 0.0, .z = rotation_rate_radps };
}

pub fn rotationVelocityEcef(position_ecef_m: math.Vec3) Error!math.Vec3 {
    if (!position_ecef_m.isFinite()) return error.NonFiniteInput;
    return rotationVectorEcef().cross(position_ecef_m);
}

/// Earth rotation expressed in north-east-down local axes.
pub fn rotationRateNed(latitude_rad: f64) Error!math.Vec3 {
    try validateLatitudeHeight(latitude_rad, 0.0);
    return .{
        .x = rotation_rate_radps * @cos(latitude_rad),
        .y = 0.0,
        .z = -rotation_rate_radps * @sin(latitude_rad),
    };
}

pub const CurvatureRadii = struct {
    meridian_m: f64,
    prime_vertical_m: f64,
};

pub fn curvatureRadii(latitude_rad: f64) Error!CurvatureRadii {
    try validateLatitudeHeight(latitude_rad, 0.0);
    const sin_lat = @sin(latitude_rad);
    const denominator = @sqrt(1.0 - first_eccentricity_squared * sin_lat * sin_lat);
    return .{
        .meridian_m = semi_major_axis_m * (1.0 - first_eccentricity_squared) /
            (denominator * denominator * denominator),
        .prime_vertical_m = semi_major_axis_m / denominator,
    };
}

/// NED transport rate of the local-level frame relative to ECEF. Velocity is
/// north/east/down in m/s.
pub fn transportRateNed(
    latitude_rad: f64,
    height_m: f64,
    velocity_ned_mps: math.Vec3,
) Error!math.Vec3 {
    try validateLatitudeHeight(latitude_rad, height_m);
    if (!velocity_ned_mps.isFinite()) return error.NonFiniteInput;
    const radii = try curvatureRadii(latitude_rad);
    const meridian = radii.meridian_m + height_m;
    const prime_vertical = radii.prime_vertical_m + height_m;
    if (!(meridian > 0.0) or !(prime_vertical > 0.0)) return error.InvalidHeight;
    return .{
        .x = velocity_ned_mps.y / prime_vertical,
        .y = -velocity_ned_mps.x / meridian,
        .z = -velocity_ned_mps.y * @tan(latitude_rad) / prime_vertical,
    };
}

test "Earth rotation velocity is omega cross ECEF position" {
    const velocity = try rotationVelocityEcef(.{ .x = semi_major_axis_m, .y = 0.0, .z = 0.0 });
    try std.testing.expectApproxEqAbs(
        rotation_rate_radps * semi_major_axis_m,
        velocity.y,
        1e-12,
    );
    try std.testing.expectEqual(@as(f64, 0.0), velocity.x);
    try std.testing.expectEqual(@as(f64, 0.0), velocity.z);
}

test "local Earth and transport rates have NED signs" {
    const earth_rate = try rotationRateNed(std.math.pi / 2.0);
    try std.testing.expectApproxEqAbs(-rotation_rate_radps, earth_rate.z, 1e-15);
    const transport = try transportRateNed(0.0, 0.0, .{ .x = 100.0, .y = 50.0, .z = 0.0 });
    try std.testing.expect(transport.x > 0.0);
    try std.testing.expect(transport.y < 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), transport.z, 1e-18);
}

test "Earth primitives refuse non-finite inputs" {
    try std.testing.expectError(error.NonFiniteInput, rotationVelocityEcef(.{
        .x = std.math.inf(f64),
        .y = 0.0,
        .z = 0.0,
    }));
    try std.testing.expectError(error.InvalidLatitude, rotationRateNed(std.math.pi));
}
