//! Standalone demonstration of the bounded UAS contingency policy.
const std = @import("std");
const uas = @import("strip").uas;

const Fixture = struct {
    name: []const u8,
    snapshot: uas.Snapshot,
};

const fixtures = [_]Fixture{
    .{ .name = "nominal", .snapshot = .{
        .link = .available,
        .fault = .none,
        .geofence = .inside,
        .designated_site_available = true,
    } },
    .{ .name = "lost-link", .snapshot = .{
        .link = .lost,
        .fault = .none,
        .geofence = .inside,
        .designated_site_available = true,
    } },
    .{ .name = "breach-and-fault", .snapshot = .{
        .link = .lost,
        .fault = .navigation_unreliable,
        .geofence = .breached,
        .designated_site_available = true,
    } },
};

pub fn main(init: std.process.Init) !u8 {
    var buffer: [2048]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};

    for (fixtures) |fixture| {
        const decision = uas.decide(fixture.snapshot);
        try writer.print(
            "{{\"fixture\":\"{s}\",\"action\":\"{s}\",\"reason\":\"{s}\"}}\n",
            .{ fixture.name, @tagName(decision.action), @tagName(decision.reason) },
        );
    }

    const simulation = try uas.simulation.run(.{
        .duration_s = 6.0,
        .step_s = 0.02,
        .seed = 42,
        .wind_force_north_n = 1.0,
        .link_loss_at_s = 3.0,
    });
    var identity_hex: [64]u8 = undefined;
    try writer.print(
        "{{\"fixture\":\"integrated-wind-link-loss\",\"action\":\"{s}\",\"steps\":{d},\"gnss_fixes\":{d},\"max_north_m\":{d},\"scenario_sha256\":\"{s}\"}}\n",
        .{
            @tagName(simulation.final_decision.action),
            simulation.step_count,
            simulation.gnss_fix_count,
            simulation.maximum_north_displacement_m,
            simulation.scenario_identity.formatHex(&identity_hex),
        },
    );
    return 0;
}
