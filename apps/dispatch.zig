//! `strip-dispatch decide` — advisory dispatch decision evidence engine.

const std = @import("std");
const strip = @import("strip");

fn usage() void {
    std.debug.print(
        \\usage:
        \\  strip-dispatch decide --id <id> --part 91|135|121|uas --role <role> \
        \\    --go|--no-go --weather opsspec_approved|platform_candidate|unapproved_ai \
        \\    [--duty-near-limit] [--weather-marginal] [--owner-pressure] [--mel-pattern-risk] \
        \\    [--gap <category>]...
        \\
    , .{});
}

fn parsePart(s: []const u8) ?strip.validation.dispatch_decision.CarrierPart {
    if (std.mem.eql(u8, s, "91")) return .@"91";
    if (std.mem.eql(u8, s, "135")) return .@"135";
    if (std.mem.eql(u8, s, "121")) return .@"121";
    if (std.mem.eql(u8, s, "uas")) return .uas;
    return null;
}

fn parseWeather(s: []const u8) ?strip.validation.dispatch_decision.WeatherSourceClass {
    if (std.mem.eql(u8, s, "opsspec_approved")) return .opsspec_approved;
    if (std.mem.eql(u8, s, "platform_candidate")) return .platform_candidate;
    if (std.mem.eql(u8, s, "unapproved_ai")) return .unapproved_ai;
    return null;
}

fn parseGap(s: []const u8) ?strip.validation.dispatch_decision.GapCategory {
    inline for (@typeInfo(strip.validation.dispatch_decision.GapCategory).@"enum".fields) |field| {
        if (std.mem.eql(u8, s, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var it = try init.minimal.args.iterateAllocator(allocator);
    defer it.deinit();
    _ = it.next();
    const sub = it.next() orelse {
        usage();
        return 2;
    };
    if (!std.mem.eql(u8, sub, "decide")) {
        usage();
        return 2;
    }

    var decision_id: ?[]const u8 = null;
    var part: ?strip.validation.dispatch_decision.CarrierPart = null;
    var role: ?[]const u8 = null;
    var requested_go: ?bool = null;
    var weather: ?strip.validation.dispatch_decision.WeatherSourceClass = null;
    var duty_near_limit = false;
    var weather_marginal = false;
    var owner_pressure = false;
    var mel_pattern_risk = false;
    var gaps_buf: [10]strip.validation.dispatch_decision.GapCategory = undefined;
    var gaps_len: usize = 0;

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--id")) {
            decision_id = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--part")) {
            part = parsePart(it.next() orelse return 2) orelse return 2;
        } else if (std.mem.eql(u8, arg, "--role")) {
            role = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--go")) {
            requested_go = true;
        } else if (std.mem.eql(u8, arg, "--no-go")) {
            requested_go = false;
        } else if (std.mem.eql(u8, arg, "--weather")) {
            weather = parseWeather(it.next() orelse return 2) orelse return 2;
        } else if (std.mem.eql(u8, arg, "--duty-near-limit")) {
            duty_near_limit = true;
        } else if (std.mem.eql(u8, arg, "--weather-marginal")) {
            weather_marginal = true;
        } else if (std.mem.eql(u8, arg, "--owner-pressure")) {
            owner_pressure = true;
        } else if (std.mem.eql(u8, arg, "--mel-pattern-risk")) {
            mel_pattern_risk = true;
        } else if (std.mem.eql(u8, arg, "--gap")) {
            const g = parseGap(it.next() orelse return 2) orelse return 2;
            if (gaps_len >= gaps_buf.len) return 2;
            gaps_buf[gaps_len] = g;
            gaps_len += 1;
        } else return 2;
    }

    const id = decision_id orelse return 2;
    const p = part orelse return 2;
    const r = role orelse return 2;
    const go = requested_go orelse return 2;
    const w = weather orelse return 2;

    const got = try strip.validation.dispatch_decision.decide(allocator, .{
        .decision_id = id,
        .carrier_part = p,
        .role = r,
        .requested_go = go,
        .weather_source_class = w,
        .explicit_gaps = gaps_buf[0..gaps_len],
        .duty_near_limit = duty_near_limit,
        .weather_marginal = weather_marginal,
        .owner_pressure = owner_pressure,
        .mel_pattern_risk = mel_pattern_risk,
    });
    defer allocator.free(got.gaps_owned);

    const json = try strip.validation.dispatch_decision.formatJson(allocator, got.decision);
    defer allocator.free(json);

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(json);
    return 0;
}
