//! Bounded local gravity models. Coordinates are local z-up; Earth rotation,
//! oblateness, latitude variation, and terrain are deliberately not modeled.

const std = @import("std");
const math = @import("../dynamics/math.zig");

pub const standard_gravity_mps2 = 9.80665;
pub const earth_mean_radius_m = 6_371_008.8;
pub const max_supported_altitude_m = 100_000.0;

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
