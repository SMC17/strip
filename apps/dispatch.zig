//! `strip-dispatch` — advisory dispatch decision + optional Gemini briefing draft.

const std = @import("std");
const strip = @import("strip");

fn usage() void {
    std.debug.print(
        \\usage:
        \\  strip-dispatch decide --id <id> --part 91|135|121|uas --role <role> \
        \\    --go|--no-go --weather opsspec_approved|platform_candidate|unapproved_ai \
        \\    [--duty-near-limit] [--weather-marginal] [--owner-pressure] [--mel-pattern-risk] \
        \\    [--gap <category>]...
        \\  strip-dispatch brief --id <id> --part 135 --role <role> --go|--no-go \
        \\    --weather <class> [--scenario "<text>"] [--live]
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

fn writeOut(init: std.process.Init, json: []const u8) !void {
    var buffer: [16384]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.writeAll(json);
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

    if (std.mem.eql(u8, sub, "decide")) {
        return try runDecide(init, allocator, &it);
    }
    if (std.mem.eql(u8, sub, "brief")) {
        return try runBrief(init, allocator, &it);
    }
    usage();
    return 2;
}

fn runDecide(init: std.process.Init, allocator: std.mem.Allocator, it: anytype) !u8 {
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
    try writeOut(init, json);
    return 0;
}

fn runBrief(init: std.process.Init, allocator: std.mem.Allocator, it: anytype) !u8 {
    var decision_id: []const u8 = "brief-draft";
    var part: strip.validation.dispatch_decision.CarrierPart = .@"135";
    var role: []const u8 = "dispatcher";
    var requested_go: bool = true;
    var weather: strip.validation.dispatch_decision.WeatherSourceClass = .platform_candidate;
    var weather_marginal = true;
    var duty_near_limit = false;
    var owner_pressure = false;
    var scenario: []const u8 = "Part 135 charter, marginal weather window, human retains go/no-go";
    var live = false;

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
        } else if (std.mem.eql(u8, arg, "--weather-marginal")) {
            weather_marginal = true;
        } else if (std.mem.eql(u8, arg, "--duty-near-limit")) {
            duty_near_limit = true;
        } else if (std.mem.eql(u8, arg, "--owner-pressure")) {
            owner_pressure = true;
        } else if (std.mem.eql(u8, arg, "--scenario")) {
            scenario = it.next() orelse return 2;
        } else if (std.mem.eql(u8, arg, "--live")) {
            live = true;
        } else return 2;
    }

    const got = try strip.validation.dispatch_decision.decide(allocator, .{
        .decision_id = decision_id,
        .carrier_part = part,
        .role = role,
        .requested_go = requested_go,
        .weather_source_class = weather,
        .duty_near_limit = duty_near_limit,
        .weather_marginal = weather_marginal,
        .owner_pressure = owner_pressure,
        .ai_participation = "gemini briefing draft; human retains release authority",
    });
    defer allocator.free(got.gaps_owned);

    const decision_json = try strip.validation.dispatch_decision.formatJson(allocator, got.decision);
    defer allocator.free(decision_json);

    var briefing_preview: []const u8 = "fixture: review weather window, duty, and escalation before release";
    var briefing_digest: []const u8 = "sha256:fixture";
    var briefing_owned = false;
    var digest_owned = false;
    defer {
        if (briefing_owned) allocator.free(briefing_preview);
        if (digest_owned) allocator.free(briefing_digest);
    }

    if (live) {
        const resolved = try strip.platform.api_key.resolve(init.io, allocator, init.environ_map);
        defer if (resolved.owned) if (resolved.key) |k| allocator.free(k);
        const key = resolved.key orelse {
            std.debug.print("brief --live needs API key\n", .{});
            return 2;
        };
        const prompt = try std.fmt.allocPrint(
            allocator,
            "You are drafting a NON-AUTHORITATIVE Part {s} dispatch briefing for a human decision-maker. " ++
                "Scenario: {s}. Engine recommendation: {s}. final_go_no_go={}. " ++
                "Write 4 short bullets: weather, legality, escalation, alternatives. " ++
                "Do not claim operational clearance. Do not invent NOTAMs.",
            .{ @tagName(part), scenario, got.decision.recommendation, got.decision.final_go_no_go },
        );
        defer allocator.free(prompt);
        const gen = try strip.platform.gemini.generateLive(
            init.io,
            allocator,
            key,
            strip.platform.gemini.default_model,
            prompt,
        );
        defer {
            allocator.free(gen.body_owned);
            allocator.free(gen.digest_owned);
            allocator.free(gen.preview_owned);
        }
        briefing_preview = try allocator.dupe(u8, gen.report.text_preview);
        briefing_owned = true;
        briefing_digest = try allocator.dupe(u8, gen.digest_owned);
        digest_owned = true;
    }

    const out = try std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.dispatch.brief.v0\",\"plane\":\"platform\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"decision\":{s},\"briefing_digest\":{f},\"briefing_preview\":{f}}}\n",
        .{
            std.mem.trim(u8, decision_json, "\r\n"),
            std.json.fmt(briefing_digest, .{}),
            std.json.fmt(briefing_preview, .{}),
        },
    );
    defer allocator.free(out);
    // decision_json already ends with }\n — embedding raw JSON object requires stripping outer and nesting carefully.
    // Fix: decision field should be embedded object; formatJson returns full object with newline.
    // The above embeds decision_json as raw which is correct if we don't wrap in quotes.
    try writeOut(init, out);
    return 0;
}
