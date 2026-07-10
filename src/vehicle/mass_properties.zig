//! Rigid mass properties with positive-definite inertia validation.

const std = @import("std");
const math = @import("../dynamics/math.zig");

pub const ValidationError = error{
    InvalidMass,
    NonFiniteCenterOfMass,
    NonFiniteInertia,
    InertiaNotPositiveDefinite,
};

/// Symmetric inertia tensor about the center of mass, expressed in body axes.
pub const Inertia = struct {
    xx: f64,
    yy: f64,
    zz: f64,
    xy: f64 = 0.0,
    xz: f64 = 0.0,
    yz: f64 = 0.0,

    pub fn validate(self: Inertia) ValidationError!void {
        const values = [_]f64{ self.xx, self.yy, self.zz, self.xy, self.xz, self.yz };
        for (values) |value| {
            if (!std.math.isFinite(value)) return error.NonFiniteInertia;
        }

        // Sylvester's criterion for this symmetric 3x3 tensor.
        const leading_2 = self.xx * self.yy - self.xy * self.xy;
        if (!(self.xx > 0.0) or !(leading_2 > 0.0) or !(self.determinant() > 0.0)) {
            return error.InertiaNotPositiveDefinite;
        }
    }

    pub fn determinant(self: Inertia) f64 {
        return self.xx * (self.yy * self.zz - self.yz * self.yz) -
            self.xy * (self.xy * self.zz - self.yz * self.xz) +
            self.xz * (self.xy * self.yz - self.yy * self.xz);
    }

    pub fn multiply(self: Inertia, vector: math.Vec3) math.Vec3 {
        return .{
            .x = self.xx * vector.x + self.xy * vector.y + self.xz * vector.z,
            .y = self.xy * vector.x + self.yy * vector.y + self.yz * vector.z,
            .z = self.xz * vector.x + self.yz * vector.y + self.zz * vector.z,
        };
    }

    pub fn solve(self: Inertia, rhs: math.Vec3) math.Vec3 {
        const det = self.determinant();
        return .{
            .x = ((self.yy * self.zz - self.yz * self.yz) * rhs.x +
                (self.xz * self.yz - self.xy * self.zz) * rhs.y +
                (self.xy * self.yz - self.xz * self.yy) * rhs.z) / det,
            .y = ((self.xz * self.yz - self.xy * self.zz) * rhs.x +
                (self.xx * self.zz - self.xz * self.xz) * rhs.y +
                (self.xy * self.xz - self.xx * self.yz) * rhs.z) / det,
            .z = ((self.xy * self.yz - self.xz * self.yy) * rhs.x +
                (self.xy * self.xz - self.xx * self.yz) * rhs.y +
                (self.xx * self.yy - self.xy * self.xy) * rhs.z) / det,
        };
    }
};

pub const MassProperties = struct {
    mass_kg: f64,
    center_of_mass_body_m: math.Vec3,
    inertia_kg_m2: Inertia,

    pub fn init(mass_kg: f64, center_of_mass_body_m: math.Vec3, inertia_kg_m2: Inertia) ValidationError!MassProperties {
        if (!(mass_kg > 0.0) or !std.math.isFinite(mass_kg)) return error.InvalidMass;
        if (!center_of_mass_body_m.isFinite()) return error.NonFiniteCenterOfMass;
        try inertia_kg_m2.validate();
        return .{
            .mass_kg = mass_kg,
            .center_of_mass_body_m = center_of_mass_body_m,
            .inertia_kg_m2 = inertia_kg_m2,
        };
    }
};

test "positive-definite inertia solves its own product" {
    const inertia = Inertia{ .xx = 3.0, .yy = 4.0, .zz = 5.0, .xy = 0.2, .xz = -0.1, .yz = 0.3 };
    try inertia.validate();
    const vector = math.Vec3{ .x = 1.0, .y = -2.0, .z = 0.5 };
    const recovered = inertia.solve(inertia.multiply(vector));
    try std.testing.expectApproxEqAbs(vector.x, recovered.x, 1e-12);
    try std.testing.expectApproxEqAbs(vector.y, recovered.y, 1e-12);
    try std.testing.expectApproxEqAbs(vector.z, recovered.z, 1e-12);
}

test "invalid mass and indefinite inertia are refused" {
    try std.testing.expectError(error.InvalidMass, MassProperties.init(
        0.0,
        math.Vec3.zero,
        .{ .xx = 1.0, .yy = 1.0, .zz = 1.0 },
    ));
    try std.testing.expectError(error.InertiaNotPositiveDefinite, MassProperties.init(
        1.0,
        math.Vec3.zero,
        .{ .xx = 1.0, .yy = 1.0, .zz = -1.0 },
    ));
}
