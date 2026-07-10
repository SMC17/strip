//! Explicit spatial and temporal reference-frame identifiers.

const std = @import("std");
const math = @import("dynamics/math.zig");

pub const SpatialFrame = enum {
    wgs84_geodetic,
    ecef,
    ned,
    enu,
    body,
    wind,
    stability,
    sensor,
};

pub const TimeReference = enum {
    simulation_monotonic,
    utc,
    tai,
};

pub fn Framed(comptime T: type) type {
    return struct {
        value: T,
        frame: SpatialFrame,
    };
}

pub const TransformError = error{
    NonFiniteInput,
    InvalidLatitude,
    InvalidLongitude,
};

fn validateLocalOrigin(latitude_rad: f64, longitude_rad: f64) TransformError!void {
    if (!std.math.isFinite(latitude_rad) or !std.math.isFinite(longitude_rad))
        return error.NonFiniteInput;
    if (@abs(latitude_rad) > std.math.pi / 2.0) return error.InvalidLatitude;
    if (@abs(longitude_rad) > std.math.pi) return error.InvalidLongitude;
}

/// Rotates an ECEF vector into north-east-down axes at a geodetic origin.
pub fn ecefToNedVector(
    vector_ecef: math.Vec3,
    latitude_rad: f64,
    longitude_rad: f64,
) TransformError!math.Vec3 {
    try validateLocalOrigin(latitude_rad, longitude_rad);
    if (!vector_ecef.isFinite()) return error.NonFiniteInput;
    const sin_lat = @sin(latitude_rad);
    const cos_lat = @cos(latitude_rad);
    const sin_lon = @sin(longitude_rad);
    const cos_lon = @cos(longitude_rad);
    return .{
        .x = -sin_lat * cos_lon * vector_ecef.x -
            sin_lat * sin_lon * vector_ecef.y + cos_lat * vector_ecef.z,
        .y = -sin_lon * vector_ecef.x + cos_lon * vector_ecef.y,
        .z = -cos_lat * cos_lon * vector_ecef.x -
            cos_lat * sin_lon * vector_ecef.y - sin_lat * vector_ecef.z,
    };
}

/// Inverse (transpose) of `ecefToNedVector`.
pub fn nedToEcefVector(
    vector_ned: math.Vec3,
    latitude_rad: f64,
    longitude_rad: f64,
) TransformError!math.Vec3 {
    try validateLocalOrigin(latitude_rad, longitude_rad);
    if (!vector_ned.isFinite()) return error.NonFiniteInput;
    const sin_lat = @sin(latitude_rad);
    const cos_lat = @cos(latitude_rad);
    const sin_lon = @sin(longitude_rad);
    const cos_lon = @cos(longitude_rad);
    return .{
        .x = -sin_lat * cos_lon * vector_ned.x -
            sin_lon * vector_ned.y - cos_lat * cos_lon * vector_ned.z,
        .y = -sin_lat * sin_lon * vector_ned.x +
            cos_lon * vector_ned.y - cos_lat * sin_lon * vector_ned.z,
        .z = cos_lat * vector_ned.x - sin_lat * vector_ned.z,
    };
}

pub fn nedToEnuVector(vector_ned: math.Vec3) TransformError!math.Vec3 {
    if (!vector_ned.isFinite()) return error.NonFiniteInput;
    return .{ .x = vector_ned.y, .y = vector_ned.x, .z = -vector_ned.z };
}

pub fn enuToNedVector(vector_enu: math.Vec3) TransformError!math.Vec3 {
    if (!vector_enu.isFinite()) return error.NonFiniteInput;
    return .{ .x = vector_enu.y, .y = vector_enu.x, .z = -vector_enu.z };
}

pub fn bodyToWorldVector(
    orientation: math.Quaternion,
    vector_body: math.Vec3,
) error{ InvalidQuaternion, NonFiniteVector }!math.Vec3 {
    return orientation.bodyToWorld(vector_body);
}

pub fn worldToBodyVector(
    orientation: math.Quaternion,
    vector_world: math.Vec3,
) error{ InvalidQuaternion, NonFiniteVector }!math.Vec3 {
    return orientation.worldToBody(vector_world);
}

test "framed values retain their declared frame" {
    const Vector3 = struct { x: f64, y: f64, z: f64 };
    const velocity = Framed(Vector3){
        .value = .{ .x = 10.0, .y = 0.0, .z = -1.0 },
        .frame = .ned,
    };
    try std.testing.expectEqual(SpatialFrame.ned, velocity.frame);
}

test "ECEF NED and ENU vector transforms round trip" {
    const latitude = 0.4;
    const longitude = -1.2;
    const ecef = math.Vec3{ .x = 12.0, .y = -3.0, .z = 8.0 };
    const ned = try ecefToNedVector(ecef, latitude, longitude);
    const recovered = try nedToEcefVector(ned, latitude, longitude);
    try std.testing.expectApproxEqAbs(ecef.x, recovered.x, 1e-12);
    try std.testing.expectApproxEqAbs(ecef.y, recovered.y, 1e-12);
    try std.testing.expectApproxEqAbs(ecef.z, recovered.z, 1e-12);
    const enu = try nedToEnuVector(ned);
    const recovered_ned = try enuToNedVector(enu);
    try std.testing.expectApproxEqAbs(ned.x, recovered_ned.x, 1e-15);
    try std.testing.expectApproxEqAbs(ned.y, recovered_ned.y, 1e-15);
    try std.testing.expectApproxEqAbs(ned.z, recovered_ned.z, 1e-15);
}

test "body world frame transforms round trip and refuse invalid quaternion" {
    const half = std.math.pi / 4.0;
    const orientation = math.Quaternion{
        .w = @cos(half),
        .x = 0.0,
        .y = 0.0,
        .z = @sin(half),
    };
    const body = math.Vec3{ .x = 1.0, .y = 2.0, .z = -0.5 };
    const world = try bodyToWorldVector(orientation, body);
    const recovered = try worldToBodyVector(orientation, world);
    try std.testing.expectApproxEqAbs(body.x, recovered.x, 1e-12);
    try std.testing.expectApproxEqAbs(body.y, recovered.y, 1e-12);
    try std.testing.expectApproxEqAbs(body.z, recovered.z, 1e-12);
    try std.testing.expectError(error.InvalidQuaternion, bodyToWorldVector(.{
        .w = 0.0,
        .x = 0.0,
        .y = 0.0,
        .z = 0.0,
    }, body));
}
