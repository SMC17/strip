//! Allocation-free point landing-gear contact and bounded ground effect.
//! World ground normal points up; penetration is positive below the plane.

const std = @import("std");

pub const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    pub const zero = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
};

pub const Gear = struct {
    spring_n_per_m: f64,
    damper_n_s_per_m: f64,
    friction_coefficient: f64,
    brake_fraction: f64 = 0.0,

    pub fn evaluate(self: Gear, penetration_m: f64, velocity_world_mps: Vec3) error{InvalidInput}!Force {
        const inputs = [_]f64{
            self.spring_n_per_m,  self.damper_n_s_per_m, self.friction_coefficient,
            self.brake_fraction,  penetration_m,         velocity_world_mps.x,
            velocity_world_mps.y, velocity_world_mps.z,
        };
        for (inputs) |value| if (!std.math.isFinite(value)) return error.InvalidInput;
        if (self.spring_n_per_m < 0.0 or self.damper_n_s_per_m < 0.0 or
            self.friction_coefficient < 0.0 or self.brake_fraction < 0.0 or
            self.brake_fraction > 1.0) return error.InvalidInput;
        if (penetration_m <= 0.0) return .{};

        // Upward normal force opposes downward velocity (negative world z).
        const normal_n = @max(0.0, self.spring_n_per_m * penetration_m -
            self.damper_n_s_per_m * velocity_world_mps.z);
        const horizontal_speed = @sqrt(
            velocity_world_mps.x * velocity_world_mps.x +
                velocity_world_mps.y * velocity_world_mps.y,
        );
        var friction = Vec3.zero;
        if (horizontal_speed > 1e-9) {
            const limit = self.friction_coefficient * normal_n;
            // Brakes command longitudinal tire force; lateral tire force
            // opposes sideslip even with brakes released.
            friction.x = -limit * self.brake_fraction * velocity_world_mps.x / horizontal_speed;
            friction.y = -limit * velocity_world_mps.y / horizontal_speed;
            const requested = @sqrt(friction.x * friction.x + friction.y * friction.y);
            if (requested > limit and requested > 0.0) {
                friction.x *= limit / requested;
                friction.y *= limit / requested;
            }
        }
        return .{
            .force_world_n = .{ .x = friction.x, .y = friction.y, .z = normal_n },
            .normal_n = normal_n,
        };
    }
};

pub const Force = struct {
    force_world_n: Vec3 = Vec3.zero,
    normal_n: f64 = 0.0,
};

/// Returns a bounded multiplier for lift magnitude. This simple correction is
/// intentionally refused below the ground plane.
pub fn groundEffectLiftFactor(height_above_ground_m: f64, span_m: f64) error{
    InvalidGeometry,
    BelowGround,
}!f64 {
    if (!std.math.isFinite(height_above_ground_m) or !std.math.isFinite(span_m) or !(span_m > 0.0))
        return error.InvalidGeometry;
    if (height_above_ground_m < 0.0) return error.BelowGround;
    const ratio = height_above_ground_m / span_m;
    if (ratio >= 1.0) return 1.0;
    return 1.0 + 0.25 * (1.0 - ratio);
}

test "contact normal force is unilateral and brake opposes travel" {
    const gear = Gear{
        .spring_n_per_m = 10_000.0,
        .damper_n_s_per_m = 500.0,
        .friction_coefficient = 0.8,
        .brake_fraction = 0.5,
    };
    const airborne = try gear.evaluate(-0.01, .{ .x = 10.0, .y = 0.0, .z = -1.0 });
    try std.testing.expectEqual(@as(f64, 0.0), airborne.normal_n);
    const contact = try gear.evaluate(0.02, .{ .x = 10.0, .y = 0.0, .z = -0.2 });
    try std.testing.expect(contact.normal_n > 0.0);
    try std.testing.expect(contact.force_world_n.x < 0.0);
    try std.testing.expect(contact.force_world_n.z >= 0.0);
    const side_load = try gear.evaluate(0.02, .{ .x = 0.0, .y = 4.0, .z = 0.0 });
    try std.testing.expect(side_load.force_world_n.y < 0.0);
}
