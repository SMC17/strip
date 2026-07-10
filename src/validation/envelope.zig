//! Bounded, multidimensional validity envelopes.
const std = @import("std");

pub const max_dimensions = 16;

pub const Axis = struct {
    variable: []const u8,
    unit: []const u8,
    minimum: f64,
    maximum: f64,

    pub fn validate(self: Axis) !void {
        if (self.variable.len == 0 or self.variable.len > 64) return error.InvalidVariable;
        if (self.unit.len == 0 or self.unit.len > 32) return error.InvalidUnit;
        if (!std.math.isFinite(self.minimum) or !std.math.isFinite(self.maximum))
            return error.NonFiniteBound;
        if (self.minimum > self.maximum) return error.InvertedBounds;
    }
};

pub const Envelope = struct {
    axes: []const Axis,

    pub fn validate(self: Envelope) !void {
        if (self.axes.len == 0) return error.EmptyEnvelope;
        if (self.axes.len > max_dimensions) return error.TooManyDimensions;
        for (self.axes, 0..) |axis, index| {
            try axis.validate();
            for (self.axes[0..index]) |prior| {
                if (std.mem.eql(u8, prior.variable, axis.variable))
                    return error.DuplicateVariable;
            }
        }
    }

    /// Values are ordered exactly as `axes`; all dimensions are required.
    pub fn contains(self: Envelope, values: []const f64) !bool {
        try self.validate();
        if (values.len != self.axes.len) return error.DimensionMismatch;
        for (self.axes, values) |axis, value| {
            if (!std.math.isFinite(value)) return error.NonFiniteValue;
            if (value < axis.minimum or value > axis.maximum) return false;
        }
        return true;
    }
};

test "multidimensional envelope requires every bounded axis" {
    const envelope: Envelope = .{ .axes = &.{
        .{ .variable = "mach", .unit = "1", .minimum = 0, .maximum = 0.4 },
        .{ .variable = "altitude", .unit = "m", .minimum = 0, .maximum = 3000 },
        .{ .variable = "angle_of_attack", .unit = "deg", .minimum = -8, .maximum = 12 },
    } };
    try std.testing.expect(try envelope.contains(&.{ 0.2, 1200, 4 }));
    try std.testing.expect(!try envelope.contains(&.{ 0.5, 1200, 4 }));
    try std.testing.expectError(error.DimensionMismatch, envelope.contains(&.{ 0.2, 1200 }));
}

test "envelope rejects duplicate dimensions and non-finite values" {
    const duplicate: Envelope = .{ .axes = &.{
        .{ .variable = "x", .unit = "m", .minimum = 0, .maximum = 1 },
        .{ .variable = "x", .unit = "m", .minimum = 0, .maximum = 2 },
    } };
    try std.testing.expectError(error.DuplicateVariable, duplicate.validate());

    const one: Envelope = .{ .axes = &.{
        .{ .variable = "x", .unit = "m", .minimum = 0, .maximum = 1 },
    } };
    try std.testing.expectError(error.NonFiniteValue, one.contains(&.{std.math.nan(f64)}));
}
