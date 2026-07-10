//! Allocation-free broad/narrow collision primitives and bounded CCD.
const std = @import("std");

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub fn scale(a: Vec3, s: f64) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
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
    pub fn lengthSquared(a: Vec3) f64 {
        return dot(a, a);
    }
};

pub const Aabb = struct {
    min: Vec3,
    max: Vec3,

    pub fn valid(self: Aabb) bool {
        return self.min.x <= self.max.x and self.min.y <= self.max.y and self.min.z <= self.max.z;
    }
    pub fn overlaps(a: Aabb, b: Aabb) bool {
        return a.min.x <= b.max.x and a.max.x >= b.min.x and
            a.min.y <= b.max.y and a.max.y >= b.min.y and
            a.min.z <= b.max.z and a.max.z >= b.min.z;
    }
    pub fn swept(a: Aabb, delta: Vec3) Aabb {
        return .{
            .min = .{
                .x = @min(a.min.x, a.min.x + delta.x),
                .y = @min(a.min.y, a.min.y + delta.y),
                .z = @min(a.min.z, a.min.z + delta.z),
            },
            .max = .{
                .x = @max(a.max.x, a.max.x + delta.x),
                .y = @max(a.max.y, a.max.y + delta.y),
                .z = @max(a.max.z, a.max.z + delta.z),
            },
        };
    }
};

pub const BroadPair = struct { a: u32, b: u32 };

pub fn BroadPhase(comptime object_capacity: usize, comptime pair_capacity: usize) type {
    return struct {
        ids: [object_capacity]u32 = undefined,
        boxes: [object_capacity]Aabb = undefined,
        count: usize = 0,
        pairs: [pair_capacity]BroadPair = undefined,
        pair_count: usize = 0,

        const Self = @This();
        pub const Error = error{ ObjectCapacityExceeded, PairCapacityExceeded, InvalidAabb };

        pub fn add(self: *Self, id: u32, box: Aabb) Error!void {
            if (!box.valid()) return error.InvalidAabb;
            if (self.count == object_capacity) return error.ObjectCapacityExceeded;
            self.ids[self.count] = id;
            self.boxes[self.count] = box;
            self.count += 1;
        }

        pub fn compute(self: *Self) Error![]const BroadPair {
            self.pair_count = 0;
            for (0..self.count) |i| {
                for (i + 1..self.count) |j| {
                    if (!self.boxes[i].overlaps(self.boxes[j])) continue;
                    if (self.pair_count == pair_capacity) return error.PairCapacityExceeded;
                    const low = @min(self.ids[i], self.ids[j]);
                    const high = @max(self.ids[i], self.ids[j]);
                    self.pairs[self.pair_count] = .{ .a = low, .b = high };
                    self.pair_count += 1;
                }
            }
            std.mem.sort(BroadPair, self.pairs[0..self.pair_count], {}, struct {
                fn less(_: void, a: BroadPair, b: BroadPair) bool {
                    return a.a < b.a or (a.a == b.a and a.b < b.b);
                }
            }.less);
            return self.pairs[0..self.pair_count];
        }
    };
}

pub const Sphere = struct { center: Vec3, radius: f64 };
pub const Plane = struct {
    /// Unit normal is required by the narrow and CCD functions.
    normal: Vec3,
    offset: f64,
};
pub const Triangle = struct { a: Vec3, b: Vec3, c: Vec3 };

pub fn sphereSphere(a: Sphere, b: Sphere) bool {
    const radius = a.radius + b.radius;
    return a.center.sub(b.center).lengthSquared() <= radius * radius;
}

pub fn spherePlane(sphere: Sphere, plane: Plane) bool {
    return @abs(sphere.center.dot(plane.normal) - plane.offset) <= sphere.radius;
}

pub fn sphereTriangle(sphere: Sphere, triangle: Triangle) bool {
    const closest = closestPointOnTriangle(sphere.center, triangle);
    return sphere.center.sub(closest).lengthSquared() <= sphere.radius * sphere.radius;
}

fn closestPointOnTriangle(point: Vec3, triangle: Triangle) Vec3 {
    const ab = triangle.b.sub(triangle.a);
    const ac = triangle.c.sub(triangle.a);
    const ap = point.sub(triangle.a);
    const d1 = ab.dot(ap);
    const d2 = ac.dot(ap);
    if (d1 <= 0.0 and d2 <= 0.0) return triangle.a;

    const bp = point.sub(triangle.b);
    const d3 = ab.dot(bp);
    const d4 = ac.dot(bp);
    if (d3 >= 0.0 and d4 <= d3) return triangle.b;
    const vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0)
        return triangle.a.add(ab.scale(d1 / (d1 - d3)));

    const cp = point.sub(triangle.c);
    const d5 = ab.dot(cp);
    const d6 = ac.dot(cp);
    if (d6 >= 0.0 and d5 <= d6) return triangle.c;
    const vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0)
        return triangle.a.add(ac.scale(d2 / (d2 - d6)));
    const va = d3 * d6 - d5 * d4;
    if (va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0)
        return triangle.b.add(triangle.c.sub(triangle.b).scale(
            (d4 - d3) / ((d4 - d3) + (d5 - d6)),
        ));

    const denominator = 1.0 / (va + vb + vc);
    return triangle.a.add(ab.scale(vb * denominator)).add(ac.scale(vc * denominator));
}

/// Segment/triangle intersection, returning normalized segment time.
pub fn segmentTriangle(start: Vec3, end: Vec3, triangle: Triangle) ?f64 {
    const epsilon = 1e-12;
    const direction = end.sub(start);
    const edge1 = triangle.b.sub(triangle.a);
    const edge2 = triangle.c.sub(triangle.a);
    const p = direction.cross(edge2);
    const determinant = edge1.dot(p);
    if (@abs(determinant) <= epsilon) return null;
    const inverse = 1.0 / determinant;
    const tvec = start.sub(triangle.a);
    const u = tvec.dot(p) * inverse;
    if (u < 0.0 or u > 1.0) return null;
    const q = tvec.cross(edge1);
    const v = direction.dot(q) * inverse;
    if (v < 0.0 or u + v > 1.0) return null;
    const t = edge2.dot(q) * inverse;
    return if (t >= 0.0 and t <= 1.0) t else null;
}

pub const CcdEnvelope = struct {
    max_speed: f64,
    max_step_seconds: f64,
    max_radius: f64,

    pub fn accepts(self: CcdEnvelope, speed: f64, step_seconds: f64, radius: f64) bool {
        return speed >= 0 and speed <= self.max_speed and
            step_seconds > 0 and step_seconds <= self.max_step_seconds and
            radius >= 0 and radius <= self.max_radius;
    }
};

/// Earliest normalized time where a moving sphere touches a plane.
pub fn sweptSpherePlane(start: Vec3, end: Vec3, radius: f64, plane: Plane) ?f64 {
    const d0 = start.dot(plane.normal) - plane.offset;
    const d1 = end.dot(plane.normal) - plane.offset;
    if (@abs(d0) <= radius) return 0.0;
    if ((d0 > radius and d1 > radius) or (d0 < -radius and d1 < -radius)) return null;
    const target = if (d0 > 0.0) radius else -radius;
    const denominator = d1 - d0;
    if (denominator == 0.0) return null;
    const t = (target - d0) / denominator;
    return if (t >= 0.0 and t <= 1.0) t else null;
}

pub fn sweptSpherePlaneInEnvelope(
    start: Vec3,
    velocity: Vec3,
    step_seconds: f64,
    radius: f64,
    plane: Plane,
    envelope: CcdEnvelope,
) error{OutsideDeclaredEnvelope}!?f64 {
    const speed = @sqrt(velocity.lengthSquared());
    if (!envelope.accepts(speed, step_seconds, radius))
        return error.OutsideDeclaredEnvelope;
    return sweptSpherePlane(start, start.add(velocity.scale(step_seconds)), radius, plane);
}

/// Earliest normalized time for two linearly moving spheres.
pub fn sweptSphereSphere(a0: Sphere, a1: Vec3, b0: Sphere, b1: Vec3) ?f64 {
    const relative_start = a0.center.sub(b0.center);
    const relative_delta = a1.sub(a0.center).sub(b1.sub(b0.center));
    const radius = a0.radius + b0.radius;
    const c = relative_start.lengthSquared() - radius * radius;
    if (c <= 0.0) return 0.0;
    const a = relative_delta.lengthSquared();
    if (a == 0.0) return null;
    const b = 2.0 * relative_start.dot(relative_delta);
    const discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0.0) return null;
    const t = (-b - @sqrt(discriminant)) / (2.0 * a);
    return if (t >= 0.0 and t <= 1.0) t else null;
}

test "broad phase emits sorted overlap pairs" {
    var broad = BroadPhase(3, 3){};
    try broad.add(9, .{ .min = .{ .x = 0, .y = 0, .z = 0 }, .max = .{ .x = 2, .y = 2, .z = 2 } });
    try broad.add(2, .{ .min = .{ .x = 1, .y = 1, .z = 1 }, .max = .{ .x = 3, .y = 3, .z = 3 } });
    try broad.add(4, .{ .min = .{ .x = 8, .y = 8, .z = 8 }, .max = .{ .x = 9, .y = 9, .z = 9 } });
    const pairs = try broad.compute();
    try std.testing.expectEqual(@as(usize, 1), pairs.len);
    try std.testing.expectEqual(BroadPair{ .a = 2, .b = 9 }, pairs[0]);
}

test "narrow primitives and CCD catch a between-tick plane crossing" {
    const plane = Plane{ .normal = .{ .x = 1, .y = 0, .z = 0 }, .offset = 0 };
    try std.testing.expect(!spherePlane(.{ .center = .{ .x = 5, .y = 0, .z = 0 }, .radius = 0.25 }, plane));
    const toi = (try sweptSpherePlaneInEnvelope(
        .{ .x = 5, .y = 0, .z = 0 },
        .{ .x = -10, .y = 0, .z = 0 },
        1.0,
        0.25,
        plane,
        .{ .max_speed = 10, .max_step_seconds = 1, .max_radius = 1 },
    )).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.475), toi, 1e-12);
    const triangle = Triangle{
        .a = .{ .x = -1, .y = -1, .z = 0 },
        .b = .{ .x = 1, .y = -1, .z = 0 },
        .c = .{ .x = 0, .y = 1, .z = 0 },
    };
    try std.testing.expect(sphereTriangle(
        .{ .center = .{ .x = 0, .y = 0, .z = 0.1 }, .radius = 0.2 },
        triangle,
    ));
    try std.testing.expect(segmentTriangle(
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 0, .y = 0, .z = -1 },
        triangle,
    ) != null);
    const sphere_toi = sweptSphereSphere(
        .{ .center = .{ .x = -5, .y = 0, .z = 0 }, .radius = 0.5 },
        .{ .x = 5, .y = 0, .z = 0 },
        .{ .center = .{ .x = 0, .y = 0, .z = 0 }, .radius = 0.5 },
        .{ .x = 0, .y = 0, .z = 0 },
    ).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.4), sphere_toi, 1e-12);
    try std.testing.expectError(error.OutsideDeclaredEnvelope, sweptSpherePlaneInEnvelope(
        .{ .x = 5, .y = 0, .z = 0 },
        .{ .x = -11, .y = 0, .z = 0 },
        1.0,
        0.25,
        plane,
        .{ .max_speed = 10, .max_step_seconds = 1, .max_radius = 1 },
    ));
}
