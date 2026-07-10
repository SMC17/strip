//! Explicit spatial and temporal reference-frame identifiers.

const std = @import("std");

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

test "framed values retain their declared frame" {
    const Vector3 = struct { x: f64, y: f64, z: f64 };
    const velocity = Framed(Vector3){
        .value = .{ .x = 10.0, .y = 0.0, .z = -1.0 },
        .frame = .ned,
    };
    try std.testing.expectEqual(SpatialFrame.ned, velocity.frame);
}
