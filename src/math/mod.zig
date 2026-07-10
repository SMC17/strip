//! Small, frame-aware three-dimensional linear algebra primitives.

const std = @import("std");

pub fn Vector3(comptime Frame: type) type {
    return struct {
        x: f64,
        y: f64,
        z: f64,

        const Self = @This();
        pub const frame = Frame;

        pub fn init(x: f64, y: f64, z: f64) Self {
            return .{ .x = x, .y = y, .z = z };
        }

        pub fn add(a: Self, b: Self) Self {
            return .init(a.x + b.x, a.y + b.y, a.z + b.z);
        }

        pub fn sub(a: Self, b: Self) Self {
            return .init(a.x - b.x, a.y - b.y, a.z - b.z);
        }

        pub fn scale(v: Self, scalar: f64) Self {
            return .init(v.x * scalar, v.y * scalar, v.z * scalar);
        }

        pub fn dot(a: Self, b: Self) f64 {
            return a.x * b.x + a.y * b.y + a.z * b.z;
        }

        pub fn cross(a: Self, b: Self) Self {
            return .init(
                a.y * b.z - a.z * b.y,
                a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x,
            );
        }

        pub fn normSquared(v: Self) f64 {
            return v.dot(v);
        }

        pub fn norm(v: Self) f64 {
            return @sqrt(v.normSquared());
        }

        pub fn normalized(v: Self) error{ZeroLength}!Self {
            const length = v.norm();
            if (length == 0.0) return error.ZeroLength;
            return v.scale(1.0 / length);
        }

        pub fn approxEqAbs(a: Self, b: Self, tolerance: f64) bool {
            return @abs(a.x - b.x) <= tolerance and
                @abs(a.y - b.y) <= tolerance and
                @abs(a.z - b.z) <= tolerance;
        }
    };
}

pub fn Matrix3(comptime From: type, comptime To: type) type {
    return struct {
        elements: [3][3]f64,

        const Self = @This();
        pub const from_frame = From;
        pub const to_frame = To;

        pub fn identity() Self {
            return .{ .elements = .{
                .{ 1.0, 0.0, 0.0 },
                .{ 0.0, 1.0, 0.0 },
                .{ 0.0, 0.0, 1.0 },
            } };
        }

        pub fn apply(self: Self, vector: Vector3(From)) Vector3(To) {
            return .init(
                self.elements[0][0] * vector.x + self.elements[0][1] * vector.y + self.elements[0][2] * vector.z,
                self.elements[1][0] * vector.x + self.elements[1][1] * vector.y + self.elements[1][2] * vector.z,
                self.elements[2][0] * vector.x + self.elements[2][1] * vector.y + self.elements[2][2] * vector.z,
            );
        }

        pub fn transpose(self: Self) Matrix3(To, From) {
            return .{ .elements = .{
                .{ self.elements[0][0], self.elements[1][0], self.elements[2][0] },
                .{ self.elements[0][1], self.elements[1][1], self.elements[2][1] },
                .{ self.elements[0][2], self.elements[1][2], self.elements[2][2] },
            } };
        }

        pub fn determinant(self: Self) f64 {
            const m = self.elements;
            return m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
        }
    };
}

pub fn Quaternion(comptime From: type, comptime To: type) type {
    return struct {
        w: f64,
        x: f64,
        y: f64,
        z: f64,

        const Self = @This();

        pub fn identity() Self {
            return .{ .w = 1.0, .x = 0.0, .y = 0.0, .z = 0.0 };
        }

        pub fn fromAxisAngle(axis: Vector3(From), angle_radians: f64) error{ZeroLength}!Self {
            const unit = try axis.normalized();
            const half = angle_radians / 2.0;
            const sine = @sin(half);
            return .{ .w = @cos(half), .x = unit.x * sine, .y = unit.y * sine, .z = unit.z * sine };
        }

        pub fn conjugate(self: Self) Quaternion(To, From) {
            return .{ .w = self.w, .x = -self.x, .y = -self.y, .z = -self.z };
        }

        pub fn rotate(self: Self, vector: Vector3(From)) Vector3(To) {
            const qv = Vector3(From).init(self.x, self.y, self.z);
            const uv = qv.cross(vector);
            const uuv = qv.cross(uv);
            const result = vector.add(uv.scale(2.0 * self.w)).add(uuv.scale(2.0));
            return .init(result.x, result.y, result.z);
        }

        pub fn toMatrix(self: Self) Matrix3(From, To) {
            const xx = self.x * self.x;
            const yy = self.y * self.y;
            const zz = self.z * self.z;
            const xy = self.x * self.y;
            const xz = self.x * self.z;
            const yz = self.y * self.z;
            const wx = self.w * self.x;
            const wy = self.w * self.y;
            const wz = self.w * self.z;
            return .{ .elements = .{
                .{ 1.0 - 2.0 * (yy + zz), 2.0 * (xy - wz), 2.0 * (xz + wy) },
                .{ 2.0 * (xy + wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz - wx) },
                .{ 2.0 * (xz - wy), 2.0 * (yz + wx), 1.0 - 2.0 * (xx + yy) },
            } };
        }
    };
}

test "vector operations preserve frame and geometry" {
    const Body = enum { body };
    const V = Vector3(Body);
    const x = V.init(1.0, 0.0, 0.0);
    const y = V.init(0.0, 1.0, 0.0);
    try std.testing.expect(x.cross(y).approxEqAbs(V.init(0.0, 0.0, 1.0), 1e-15));
    try std.testing.expectApproxEqAbs(0.0, x.dot(y), 1e-15);
}

test "quaternion and matrix agree on rotation" {
    const A = enum { a };
    const B = enum { b };
    const axis = Vector3(A).init(0.0, 0.0, 1.0);
    const q = try Quaternion(A, B).fromAxisAngle(axis, std.math.pi / 2.0);
    const input = Vector3(A).init(1.0, 0.0, 0.0);
    const expected = Vector3(B).init(0.0, 1.0, 0.0);
    try std.testing.expect(q.rotate(input).approxEqAbs(expected, 1e-14));
    try std.testing.expect(q.toMatrix().apply(input).approxEqAbs(expected, 1e-14));
    try std.testing.expectApproxEqAbs(1.0, q.toMatrix().determinant(), 1e-14);
}
