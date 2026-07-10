//! Small, allocation-free Euclidean and quaternion types for the dynamics lane.

const std = @import("std");

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    pub const zero = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn scale(a: Vec3, scalar: f64) Vec3 {
        return .{ .x = a.x * scalar, .y = a.y * scalar, .z = a.z * scalar };
    }

    pub fn dot(a: Vec3, b: Vec3) f64 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn normSquared(a: Vec3) f64 {
        return dot(a, a);
    }

    pub fn isFinite(a: Vec3) bool {
        return std.math.isFinite(a.x) and std.math.isFinite(a.y) and std.math.isFinite(a.z);
    }
};

/// Hamilton quaternion representing a body-to-world active rotation.
pub const Quaternion = struct {
    w: f64,
    x: f64,
    y: f64,
    z: f64,

    pub const identity = Quaternion{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };

    pub fn add(a: Quaternion, b: Quaternion) Quaternion {
        return .{ .w = a.w + b.w, .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn scale(q: Quaternion, scalar: f64) Quaternion {
        return .{ .w = q.w * scalar, .x = q.x * scalar, .y = q.y * scalar, .z = q.z * scalar };
    }

    pub fn multiply(a: Quaternion, b: Quaternion) Quaternion {
        return .{
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        };
    }

    pub fn normSquared(q: Quaternion) f64 {
        return q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z;
    }

    pub fn isFinite(q: Quaternion) bool {
        return std.math.isFinite(q.w) and std.math.isFinite(q.x) and
            std.math.isFinite(q.y) and std.math.isFinite(q.z);
    }

    pub fn normalized(q: Quaternion) error{InvalidQuaternion}!Quaternion {
        const squared = normSquared(q);
        if (!(squared > 0.0) or !std.math.isFinite(squared)) return error.InvalidQuaternion;
        const magnitude = @sqrt(squared);
        return scale(q, 1.0 / magnitude);
    }

    pub fn conjugate(q: Quaternion) Quaternion {
        return .{ .w = q.w, .x = -q.x, .y = -q.y, .z = -q.z };
    }

    pub fn inverse(q: Quaternion) error{InvalidQuaternion}!Quaternion {
        const squared = normSquared(q);
        if (!(squared > 0.0) or !std.math.isFinite(squared)) return error.InvalidQuaternion;
        return q.conjugate().scale(1.0 / squared);
    }

    pub fn rotate(q_raw: Quaternion, vector: Vec3) error{ InvalidQuaternion, NonFiniteVector }!Vec3 {
        if (!vector.isFinite()) return error.NonFiniteVector;
        const q = try q_raw.normalized();
        const u = Vec3{ .x = q.x, .y = q.y, .z = q.z };
        return vector.add(u.cross(vector).scale(2.0 * q.w)).add(u.cross(u.cross(vector)).scale(2.0));
    }

    pub fn bodyToWorld(q: Quaternion, vector_body: Vec3) error{ InvalidQuaternion, NonFiniteVector }!Vec3 {
        return q.rotate(vector_body);
    }

    pub fn worldToBody(q: Quaternion, vector_world: Vec3) error{ InvalidQuaternion, NonFiniteVector }!Vec3 {
        return (try q.inverse()).rotate(vector_world);
    }

    pub fn derivativeBodyRate(q: Quaternion, angular_velocity_body: Vec3) Quaternion {
        const omega = Quaternion{
            .w = 0.0,
            .x = angular_velocity_body.x,
            .y = angular_velocity_body.y,
            .z = angular_velocity_body.z,
        };
        return multiply(q, omega).scale(0.5);
    }
};

test "unit quaternion rotation preserves vector norm" {
    const half = std.math.pi / 4.0;
    const q = Quaternion{ .w = @cos(half), .x = 0.0, .y = 0.0, .z = @sin(half) };
    const rotated = try q.rotate(.{ .x = 1.0, .y = 0.0, .z = 0.0 });
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), rotated.x, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), rotated.y, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), rotated.normSquared(), 1e-12);
}

test "quaternion inverse round trips body and world vectors" {
    const half = std.math.pi / 6.0;
    const q = Quaternion{ .w = @cos(half), .x = @sin(half), .y = 0.0, .z = 0.0 };
    const body = Vec3{ .x = 2.0, .y = -1.0, .z = 0.5 };
    const world = try q.bodyToWorld(body);
    const recovered = try q.worldToBody(world);
    try std.testing.expectApproxEqAbs(body.x, recovered.x, 1e-12);
    try std.testing.expectApproxEqAbs(body.y, recovered.y, 1e-12);
    try std.testing.expectApproxEqAbs(body.z, recovered.z, 1e-12);
}

test "quaternion rotation refuses zero and non-finite inputs" {
    try std.testing.expectError(error.InvalidQuaternion, (Quaternion{
        .w = 0.0,
        .x = 0.0,
        .y = 0.0,
        .z = 0.0,
    }).rotate(.{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    try std.testing.expectError(error.NonFiniteVector, Quaternion.identity.rotate(.{
        .x = std.math.nan(f64),
        .y = 0.0,
        .z = 0.0,
    }));
}
