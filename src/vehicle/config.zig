//! Strict, bounded vehicle configuration data.
const std = @import("std");

pub const Axis = struct {
    variable: []const u8,
    unit: []const u8,
    minimum: f64,
    maximum: f64,

    pub fn validate(self: Axis) !void {
        try bounded(self.variable, 1, 64);
        try bounded(self.unit, 1, 32);
        if (!std.math.isFinite(self.minimum) or !std.math.isFinite(self.maximum))
            return error.NonFiniteBound;
        if (self.minimum > self.maximum) return error.InvertedBounds;
    }
};

pub const Envelope = struct {
    axes: []const Axis,

    pub fn validate(self: Envelope) !void {
        if (self.axes.len == 0 or self.axes.len > 16) return error.InvalidDimensionCount;
        for (self.axes, 0..) |axis, index| {
            try axis.validate();
            for (self.axes[0..index]) |prior| {
                if (std.mem.eql(u8, axis.variable, prior.variable))
                    return error.DuplicateVariable;
            }
        }
    }
};

pub const Inertia = struct {
    xx: f64,
    yy: f64,
    zz: f64,
    xy: f64 = 0,
    xz: f64 = 0,
    yz: f64 = 0,

    pub fn validate(self: Inertia) !void {
        inline for (.{ self.xx, self.yy, self.zz, self.xy, self.xz, self.yz }) |value| {
            if (!std.math.isFinite(value)) return error.NonFiniteInertia;
            if (@abs(value) > 1.0e12) return error.InertiaOutOfRange;
        }
        if (self.xx <= 0 or self.yy <= 0 or self.zz <= 0) return error.NonPositiveInertia;
        const minor2 = self.xx * self.yy - self.xy * self.xy;
        const determinant =
            self.xx * (self.yy * self.zz - self.yz * self.yz) -
            self.xy * (self.xy * self.zz - self.yz * self.xz) +
            self.xz * (self.xy * self.yz - self.yy * self.xz);
        if (!std.math.isFinite(minor2) or !std.math.isFinite(determinant) or
            minor2 <= 0 or determinant <= 0)
            return error.InertiaNotPositiveDefinite;
    }
};

pub const VehicleConfig = struct {
    schema: []const u8,
    id: []const u8,
    version: []const u8,
    description: []const u8,
    mass_kg: f64,
    reference_area_m2: f64,
    reference_span_m: f64,
    reference_chord_m: f64,
    inertia_kg_m2: Inertia,
    validity_envelope: Envelope,
    source_ids: []const []const u8,

    pub fn validate(self: VehicleConfig) !void {
        if (!std.mem.eql(u8, self.schema, "strip.vehicle.v1")) return error.UnsupportedSchema;
        try bounded(self.id, 1, 96);
        try bounded(self.version, 1, 64);
        try bounded(self.description, 1, 512);
        try positiveBounded(self.mass_kg, 0.001, 1.0e8);
        try positiveBounded(self.reference_area_m2, 1.0e-6, 1.0e7);
        try positiveBounded(self.reference_span_m, 1.0e-5, 1.0e5);
        try positiveBounded(self.reference_chord_m, 1.0e-5, 1.0e5);
        try self.inertia_kg_m2.validate();
        try self.validity_envelope.validate();
        if (self.source_ids.len == 0 or self.source_ids.len > 32)
            return error.InvalidSourceCount;
        for (self.source_ids, 0..) |source_id, index| {
            try bounded(source_id, 1, 96);
            for (self.source_ids[0..index]) |prior| {
                if (std.mem.eql(u8, source_id, prior)) return error.DuplicateSourceId;
            }
        }
    }
};

fn bounded(value: []const u8, minimum: usize, maximum: usize) !void {
    if (value.len < minimum or value.len > maximum) return error.InvalidTextLength;
}

fn positiveBounded(value: f64, minimum: f64, maximum: f64) !void {
    if (!std.math.isFinite(value)) return error.NonFiniteValue;
    if (value < minimum or value > maximum) return error.ValueOutOfRange;
}

test "vehicle config rejects coupled non-positive-definite inertia" {
    var config: VehicleConfig = .{
        .schema = "strip.vehicle.v1",
        .id = "bad-inertia",
        .version = "1",
        .description = "A bounded negative fixture.",
        .mass_kg = 1,
        .reference_area_m2 = 1,
        .reference_span_m = 1,
        .reference_chord_m = 1,
        .inertia_kg_m2 = .{ .xx = 1, .yy = 1, .zz = 1, .xy = 2 },
        .validity_envelope = .{ .axes = &.{
            .{ .variable = "mach", .unit = "1", .minimum = 0, .maximum = 0.2 },
        } },
        .source_ids = &.{"source"},
    };
    try std.testing.expectError(error.InertiaNotPositiveDefinite, config.validate());
}
