//! Minimal allocation-free geometry types owned by the fixed-wing lane.

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

    pub fn conjugate(q: Quaternion) Quaternion {
        return .{ .w = q.w, .x = -q.x, .y = -q.y, .z = -q.z };
    }

    pub fn rotate(q_raw: Quaternion, vector: Vec3) Vec3 {
        const norm = q_raw.w * q_raw.w + q_raw.x * q_raw.x + q_raw.y * q_raw.y + q_raw.z * q_raw.z;
        if (!(norm > 0.0) or !std.math.isFinite(norm)) return Vec3.zero;
        const inverse_magnitude = 1.0 / @sqrt(norm);
        const q = Quaternion{
            .w = q_raw.w * inverse_magnitude,
            .x = q_raw.x * inverse_magnitude,
            .y = q_raw.y * inverse_magnitude,
            .z = q_raw.z * inverse_magnitude,
        };
        const uxv = Vec3{
            .x = q.y * vector.z - q.z * vector.y,
            .y = q.z * vector.x - q.x * vector.z,
            .z = q.x * vector.y - q.y * vector.x,
        };
        const u_cross_uxv = Vec3{
            .x = q.y * uxv.z - q.z * uxv.y,
            .y = q.z * uxv.x - q.x * uxv.z,
            .z = q.x * uxv.y - q.y * uxv.x,
        };
        return .{
            .x = vector.x + 2.0 * (q.w * uxv.x + u_cross_uxv.x),
            .y = vector.y + 2.0 * (q.w * uxv.y + u_cross_uxv.y),
            .z = vector.z + 2.0 * (q.w * uxv.z + u_cross_uxv.z),
        };
    }
};
