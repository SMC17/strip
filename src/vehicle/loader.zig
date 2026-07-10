//! Dependency-free strict JSON loader for bounded vehicle configurations.
const std = @import("std");
const config = @import("config.zig");

pub const max_input_bytes = 128 * 1024;
pub const ParsedVehicleConfig = std.json.Parsed(config.VehicleConfig);

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !ParsedVehicleConfig {
    if (bytes.len == 0) return error.EmptyInput;
    if (bytes.len > max_input_bytes) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(config.VehicleConfig, allocator, bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

test "strict vehicle loader accepts typed bounded fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/vehicle.valid.json",
        std.testing.allocator,
        .limited(max_input_bytes),
    );
    defer std.testing.allocator.free(bytes);
    var parsed = try parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("strip.demo-uas", parsed.value.id);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.validity_envelope.axes.len);
}

test "strict vehicle loader rejects semantically invalid fixture" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/vehicle.invalid.json",
        std.testing.allocator,
        .limited(max_input_bytes),
    );
    defer std.testing.allocator.free(bytes);
    try std.testing.expectError(
        error.ValueOutOfRange,
        parse(std.testing.allocator, bytes),
    );
}

test "strict vehicle loader rejects unknown fields" {
    const bytes =
        \\{"schema":"strip.vehicle.v1","id":"x","version":"1","description":"x",
        \\"mass_kg":1,"reference_area_m2":1,"reference_span_m":1,"reference_chord_m":1,
        \\"inertia_kg_m2":{"xx":1,"yy":1,"zz":1},
        \\"validity_envelope":{"axes":[{"variable":"mach","unit":"1","minimum":0,"maximum":1}]},
        \\"source_ids":["source"],"unreviewed":true}
    ;
    try std.testing.expectError(error.UnknownField, parse(std.testing.allocator, bytes));
}
