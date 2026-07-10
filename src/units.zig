//! Distinct SI quantity types for Strip's public model boundaries.

const std = @import("std");

pub const UnitError = error{NonFinite};

fn requireFinite(value: f64) UnitError!f64 {
    if (!std.math.isFinite(value)) return error.NonFinite;
    return value;
}

pub const GeopotentialAltitude = struct {
    meters: f64,

    pub fn init(meters: f64) UnitError!GeopotentialAltitude {
        return .{ .meters = try requireFinite(meters) };
    }
};

pub const Temperature = struct { kelvin: f64 };
pub const Pressure = struct { pascals: f64 };
pub const Density = struct { kilograms_per_cubic_meter: f64 };
pub const Speed = struct { meters_per_second: f64 };

test "altitude rejects non-finite inputs" {
    try std.testing.expectError(error.NonFinite, GeopotentialAltitude.init(std.math.nan(f64)));
    try std.testing.expectError(error.NonFinite, GeopotentialAltitude.init(std.math.inf(f64)));
}
