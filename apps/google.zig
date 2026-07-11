//! `strip-google` — Google/DeepMind platform catalog + Gemini client.

const std = @import("std");
const strip = @import("strip");

fn usage() void {
    std.debug.print(
        \\usage:
        \\  strip-google catalog
        \\  strip-google gemini status
        \\  strip-google gemini fixture [--model <id>]
        \\  strip-google gemini --live [--model <id>] "<prompt>"
        \\
        \\API key: GEMINI_API_KEY or GOOGLE_API_KEY from https://aistudio.google.com/apikey
        \\
    , .{});
}

fn writeOut(init: std.process.Init, json: []const u8) !void {
    var buffer: [8192]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(json);
}

fn apiKey(init: std.process.Init) ?[]const u8 {
    if (init.environ_map.get("GOOGLE_API_KEY")) |k| return k;
    return init.environ_map.get("GEMINI_API_KEY");
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const cmd = it.next() orelse "catalog";

    if (std.mem.eql(u8, cmd, "catalog")) {
        const json = try strip.platform.google_catalog.formatCatalogJson(allocator);
        defer allocator.free(json);
        try writeOut(init, json);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "gemini")) {
        var model: []const u8 = strip.platform.gemini.default_model;
        var live = false;
        var fixture = false;
        var status = false;
        var prompt: ?[]const u8 = null;

        while (it.next()) |arg| {
            if (std.mem.eql(u8, arg, "status")) {
                status = true;
            } else if (std.mem.eql(u8, arg, "fixture")) {
                fixture = true;
            } else if (std.mem.eql(u8, arg, "--live")) {
                live = true;
            } else if (std.mem.eql(u8, arg, "--model")) {
                model = it.next() orelse return 2;
            } else if (prompt == null and arg.len > 0 and arg[0] != '-') {
                prompt = arg;
            } else return 2;
        }

        if (status or (!fixture and !live and prompt == null)) {
            const report = strip.platform.gemini.statusReport(apiKey(init) != null, model);
            const json = try strip.platform.gemini.formatReport(allocator, report);
            defer allocator.free(json);
            try writeOut(init, json);
            return 0;
        }
        if (fixture) {
            const got = try strip.platform.gemini.generateFixture(allocator, model);
            defer allocator.free(got.digest_owned);
            const json = try strip.platform.gemini.formatReport(allocator, got.report);
            defer allocator.free(json);
            try writeOut(init, json);
            return 0;
        }
        if (live) {
            const key = apiKey(init) orelse {
                std.debug.print("set GEMINI_API_KEY or GOOGLE_API_KEY\n", .{});
                return 2;
            };
            const p = prompt orelse {
                std.debug.print("live mode requires a prompt string\n", .{});
                return 2;
            };
            const got = try strip.platform.gemini.generateLive(init.io, allocator, key, model, p);
            defer {
                allocator.free(got.digest_owned);
                allocator.free(got.body_owned);
                allocator.free(got.preview_owned);
            }
            const json = try strip.platform.gemini.formatReport(allocator, got.report);
            defer allocator.free(json);
            try writeOut(init, json);
            return 0;
        }
        usage();
        return 2;
    }

    usage();
    return 2;
}
