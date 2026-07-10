//! External-adapter contracts. Implementations must declare availability.
const std = @import("std");

pub const jsbsim = @import("jsbsim.zig");
pub const openvsp = @import("openvsp.zig");
pub const openvsp_tessellation = @import("openvsp_tessellation.zig");
pub const openvsp_export = @import("openvsp_export.zig");

pub const Availability = union(enum) {
    available: struct { implementation: []const u8, version: []const u8 },
    unavailable: []const u8,
};

pub const Adapter = struct {
    name: []const u8,
    availability: Availability,
    context: ?*anyopaque = null,
    exchangeFn: ?*const fn (*anyopaque, []const u8, []u8) anyerror!usize = null,

    pub fn exchange(self: Adapter, request: []const u8, output: []u8) !usize {
        switch (self.availability) {
            .unavailable => return error.AdapterUnavailable,
            .available => {},
        }
        const function = self.exchangeFn orelse return error.MissingImplementation;
        const context = self.context orelse return error.MissingImplementation;
        return function(context, request, output);
    }
};

pub const public_catalog = [_]Adapter{
    .{ .name = "JSBSim", .availability = .{ .unavailable = "contract only; executable not linked" } },
    .{ .name = "OpenVSP", .availability = .{ .unavailable = "contract only; executable not linked" } },
    .{ .name = "OpenMDAO", .availability = .{ .unavailable = "contract only; Python bridge not linked" } },
    .{ .name = "FMI", .availability = .{ .unavailable = "contract only; FMU runtime not linked" } },
    .{ .name = "ROS2-DDS", .availability = .{ .unavailable = "contract only; middleware not linked" } },
    .{ .name = "HLA-DIS", .availability = .{ .unavailable = "contract only; federation runtime not linked" } },
    .{ .name = "MAVLink", .availability = .{ .unavailable = "contract only; transport not linked" } },
    .{ .name = "public-weather-airspace", .availability = .{ .unavailable = "contract only; network access excluded from kernel" } },
};

test {
    _ = jsbsim;
    _ = openvsp;
    _ = openvsp_tessellation;
    _ = openvsp_export;
}

test "unavailable scaffold fails explicitly" {
    const adapter: Adapter = .{
        .name = "external-simulator",
        .availability = .{ .unavailable = "not linked in this build" },
    };
    var output: [8]u8 = undefined;
    try std.testing.expectError(error.AdapterUnavailable, adapter.exchange("request", &output));
}

test "public adapter catalog cannot imply linked implementations" {
    for (public_catalog) |adapter| switch (adapter.availability) {
        .unavailable => {},
        .available => return error.TestUnexpectedResult,
    };
}
