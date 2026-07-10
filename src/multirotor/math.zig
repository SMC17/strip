//! Allocation-free math types kept local so this lane remains independently testable.

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
    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    pub fn normSquared(a: Vec3) f64 {
        return a.x * a.x + a.y * a.y + a.z * a.z;
    }
    pub fn isFinite(a: Vec3) bool {
        return std.math.isFinite(a.x) and std.math.isFinite(a.y) and std.math.isFinite(a.z);
    }
};

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
    pub fn normalized(q: Quaternion) error{ZeroNorm}!Quaternion {
        const norm = @sqrt(q.normSquared());
        if (!(norm > 0.0) or !std.math.isFinite(norm)) return error.ZeroNorm;
        return q.scale(1.0 / norm);
    }
    pub fn rotate(q_raw: Quaternion, vector: Vec3) Vec3 {
        const q = q_raw.normalized() catch return Vec3.zero;
        const u = Vec3{ .x = q.x, .y = q.y, .z = q.z };
        return vector.add(u.cross(vector).scale(2.0 * q.w)).add(u.cross(u.cross(vector)).scale(2.0));
    }
    pub fn derivativeBodyRate(q: Quaternion, angular_velocity_body: Vec3) Quaternion {
        return q.multiply(.{
            .w = 0.0,
            .x = angular_velocity_body.x,
            .y = angular_velocity_body.y,
            .z = angular_velocity_body.z,
        }).scale(0.5);
    }
};
