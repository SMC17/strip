//! `strip-weathernext` — platform-plane WeatherNext client (never authoritative).

const std = @import("std");
const strip = @import("strip");

fn usage() void {
    std.debug.print(
        \\usage:
        \\  strip-weathernext status
        \\  strip-weathernext fixture
        \\  strip-weathernext fetch --live
        \\
        \\Live fetch requires STRIP_WEATHERNEXT_ENDPOINT (optional STRIP_WEATHERNEXT_TOKEN).
        \\
    , .{});
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const cmd = it.next() orelse "status";

    const endpoint = init.environ_map.get("STRIP_WEATHERNEXT_ENDPOINT");
    const token = init.environ_map.get("STRIP_WEATHERNEXT_TOKEN");

    if (std.mem.eql(u8, cmd, "status")) {
        const report = strip.platform.weathernext.statusReport(endpoint != null);
        const json = try strip.platform.weathernext.formatReport(allocator, report);
        defer allocator.free(json);
        try writeOut(init, json);
        return 0;
    }
    if (std.mem.eql(u8, cmd, "fixture")) {
        const got = try strip.platform.weathernext.fetchFixture(allocator);
        defer allocator.free(got.digest_owned);
        const json = try strip.platform.weathernext.formatReport(allocator, got.report);
        defer allocator.free(json);
        try writeOut(init, json);
        return 0;
    }
    if (std.mem.eql(u8, cmd, "fetch")) {
        const live = blk: {
            while (it.next()) |arg| {
                if (std.mem.eql(u8, arg, "--live")) break :blk true;
            }
            break :blk false;
        };
        if (!live) {
            usage();
            return 2;
        }
        const ep = endpoint orelse {
            std.debug.print("STRIP_WEATHERNEXT_ENDPOINT is required for --live\n", .{});
            return 2;
        };
        const got = try strip.platform.weathernext.fetchLive(init.io, allocator, ep, token);
        defer {
            allocator.free(got.digest_owned);
            allocator.free(got.body_owned);
        }
        const json = try strip.platform.weathernext.formatReport(allocator, got.report);
        defer allocator.free(json);
        try writeOut(init, json);
        return 0;
    }
    usage();
    return 2;
}

fn writeOut(init: std.process.Init, json: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(json);
}
