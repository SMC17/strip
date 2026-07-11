//! `strip-weathernext` — platform-plane weather client (never authoritative).
//! Defaults to WeatherNext Graph until WN2 leaves open beta.
//! Interim live: Open-Meteo or NOAA/NWS (Vertex WeatherNext still EAP).

const std = @import("std");
const strip = @import("strip");

fn usage() void {
    std.debug.print(
        \\usage:
        \\  strip-weathernext status
        \\  strip-weathernext fixture
        \\  strip-weathernext fetch --live [--interim open-meteo|nws]
        \\
        \\Live: STRIP_WEATHERNEXT_ENDPOINT, or --interim until Vertex WN is GA.
        \\Vertex WeatherNext 2 remains EAP (no public REST); Maps Weather API needs OAuth.
        \\
    , .{});
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const cmd = it.next() orelse "status";

    const endpoint_env = init.environ_map.get("STRIP_WEATHERNEXT_ENDPOINT");
    const token = init.environ_map.get("STRIP_WEATHERNEXT_TOKEN");

    if (std.mem.eql(u8, cmd, "status")) {
        const report = strip.platform.weathernext.statusReport(endpoint_env != null);
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
        var live = false;
        var interim: ?[]const u8 = null;
        while (it.next()) |arg| {
            if (std.mem.eql(u8, arg, "--live")) {
                live = true;
            } else if (std.mem.eql(u8, arg, "--interim")) {
                interim = it.next() orelse return 2;
            } else return 2;
        }
        if (!live) {
            usage();
            return 2;
        }
        var model_family: []const u8 = strip.platform.weathernext.default_model_family;
        var user_agent: ?[]const u8 = null;
        const ep = blk: {
            if (interim) |name| {
                if (std.mem.eql(u8, name, "open-meteo")) {
                    model_family = "Open-Meteo (interim until WeatherNext GA)";
                    break :blk strip.platform.weathernext.interim_open_meteo_endpoint;
                }
                if (std.mem.eql(u8, name, "nws")) {
                    model_family = "NOAA/NWS (interim until WeatherNext GA)";
                    user_agent = strip.platform.weathernext.nws_user_agent;
                    break :blk strip.platform.weathernext.interim_nws_points_endpoint;
                }
                std.debug.print("unknown --interim {s} (supported: open-meteo, nws)\n", .{name});
                return 2;
            }
            break :blk endpoint_env orelse {
                std.debug.print("STRIP_WEATHERNEXT_ENDPOINT required, or pass --interim open-meteo|nws\n", .{});
                return 2;
            };
        };
        const got = try strip.platform.weathernext.fetchLiveWithUserAgent(
            init.io,
            allocator,
            ep,
            token,
            model_family,
            user_agent,
        );
        defer {
            allocator.free(got.digest_owned);
            allocator.free(got.body_owned);
        }
        const json = try strip.platform.weathernext.formatReport(allocator, got.report);
        defer allocator.free(json);
        try writeOut(init, json);
        const ok = if (got.report.http_status) |s| s >= 200 and s < 300 else false;
        return if (ok) 0 else 1;
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
