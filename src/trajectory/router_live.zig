//! Live multi-model dispatch (platform plane). Never called from verify.

const std = @import("std");
const router = @import("router.zig");
const gemini = @import("../platform/gemini.zig");
const openrouter = @import("../platform/openrouter.zig");
const api_key = @import("../platform/api_key.zig");

pub const LiveReport = struct {
    intent: router.Intent,
    selected_model: []const u8,
    provider: router.Provider,
    score: f64,
    transport: []const u8,
    http_status: ?u16,
    body_digest: ?[]const u8,
    text_preview: []const u8,
    google_key: bool,
    openrouter_key: bool,
};

fn openRouterModelId(model_id: []const u8) []const u8 {
    if (std.mem.eql(u8, model_id, "grok-4.5")) return "x-ai/grok-4.5";
    if (std.mem.eql(u8, model_id, "claude-opus")) return "anthropic/claude-sonnet-4";
    if (std.mem.eql(u8, model_id, "gpt-flagship")) return "openai/gpt-4.1-mini";
    if (std.mem.eql(u8, model_id, "gemini-3.5-flash")) return "google/gemini-2.5-flash";
    return openrouter.default_model;
}

fn prepareRegistry(live_gemini: bool, live_or: bool) [5]router.ModelConfig {
    var registry = router.fixtureRegistry(live_gemini, live_or);
    if (live_or) {
        registry[1].live_capable = true;
        registry[2].live_capable = true;
        registry[3].live_capable = true;
        registry[1].p_success = 0.92;
        registry[2].p_success = 0.93;
        registry[3].p_success = 0.90;
    }
    if (live_gemini) {
        registry[4].live_capable = true;
        registry[4].p_success = 0.91;
    }
    return registry;
}

fn selectLive(registry: []const router.ModelConfig, intent: router.Intent) !router.Selection {
    var best: ?router.Selection = null;
    var considered: usize = 0;
    for (registry) |m| {
        if (m.provider == .strip_local) continue;
        if (!m.live_capable) continue;
        var ok = false;
        for (m.intents) |i| if (i == intent) {
            ok = true;
            break;
        };
        if (!ok) continue;
        considered += 1;
        const s = router.score(m, .{});
        if (best == null or s > best.?.score) {
            best = .{
                .model_id = m.id,
                .provider = m.provider,
                .score = s,
                .intent = intent,
                .candidates_considered = 0,
                .live_capable = true,
            };
        }
    }
    var result = best orelse return error.NoLiveModelForIntent;
    result.candidates_considered = considered;
    return result;
}

pub fn status(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: anytype,
    intent: router.Intent,
) !LiveReport {
    const g = try api_key.resolve(io, allocator, environ);
    defer if (g.owned) if (g.key) |k| allocator.free(k);
    const o = try api_key.resolveOpenRouter(io, allocator, environ);
    defer if (o.owned) if (o.key) |k| allocator.free(k);

    const registry = prepareRegistry(g.key != null, o.key != null);
    const sel = selectLive(&registry, intent) catch try router.select(&registry, intent, .{});
    return .{
        .intent = intent,
        .selected_model = sel.model_id,
        .provider = sel.provider,
        .score = sel.score,
        .transport = "status_only",
        .http_status = null,
        .body_digest = null,
        .text_preview = "",
        .google_key = g.key != null,
        .openrouter_key = o.key != null,
    };
}

pub fn dispatchLive(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: anytype,
    intent: router.Intent,
    prompt: []const u8,
) !struct {
    report: LiveReport,
    digest_owned: []u8,
    preview_owned: []u8,
    body_owned: []u8,
} {
    const g = try api_key.resolve(io, allocator, environ);
    defer if (g.owned) if (g.key) |k| allocator.free(k);
    const o = try api_key.resolveOpenRouter(io, allocator, environ);
    defer if (o.owned) if (o.key) |k| allocator.free(k);

    if (g.key == null and o.key == null) return error.NoLiveProviderKey;

    const registry = prepareRegistry(g.key != null, o.key != null);
    const sel = try selectLive(&registry, intent);

    // Prefer Gemini direct when selected provider is gemini and Google key exists.
    if (sel.provider == .gemini and g.key != null) {
        const got = try gemini.generateLive(io, allocator, g.key.?, gemini.default_model, prompt);
        return .{
            .report = .{
                .intent = intent,
                .selected_model = gemini.default_model,
                .provider = .gemini,
                .score = sel.score,
                .transport = "gemini_generateContent",
                .http_status = got.report.http_status,
                .body_digest = got.digest_owned,
                .text_preview = got.preview_owned,
                .google_key = true,
                .openrouter_key = o.key != null,
            },
            .digest_owned = got.digest_owned,
            .preview_owned = got.preview_owned,
            .body_owned = got.body_owned,
        };
    }

    if (o.key == null) {
        // Fall back to Gemini for any intent if only Google key exists.
        if (g.key == null) return error.NoLiveProviderKey;
        const got = try gemini.generateLive(io, allocator, g.key.?, gemini.default_model, prompt);
        return .{
            .report = .{
                .intent = intent,
                .selected_model = gemini.default_model,
                .provider = .gemini,
                .score = sel.score,
                .transport = "gemini_generateContent",
                .http_status = got.report.http_status,
                .body_digest = got.digest_owned,
                .text_preview = got.preview_owned,
                .google_key = true,
                .openrouter_key = false,
            },
            .digest_owned = got.digest_owned,
            .preview_owned = got.preview_owned,
            .body_owned = got.body_owned,
        };
    }

    const or_model = openRouterModelId(sel.model_id);
    const got = try openrouter.chatLive(io, allocator, o.key.?, or_model, prompt);
    return .{
        .report = .{
            .intent = intent,
            .selected_model = or_model,
            .provider = .openrouter,
            .score = sel.score,
            .transport = "openrouter_chat_completions",
            .http_status = got.report.http_status,
            .body_digest = got.digest_owned,
            .text_preview = got.preview_owned,
            .google_key = g.key != null,
            .openrouter_key = true,
        },
        .digest_owned = got.digest_owned,
        .preview_owned = got.preview_owned,
        .body_owned = got.body_owned,
    };
}

pub fn formatLiveJson(allocator: std.mem.Allocator, report: LiveReport) ![]u8 {
    const status_txt = if (report.http_status) |s|
        try std.fmt.allocPrint(allocator, "{d}", .{s})
    else
        try allocator.dupe(u8, "null");
    defer allocator.free(status_txt);
    const digest_txt = if (report.body_digest) |d|
        try std.fmt.allocPrint(allocator, "\"{s}\"", .{d})
    else
        try allocator.dupe(u8, "null");
    defer allocator.free(digest_txt);
    return std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.trajectory.router.live.v0\",\"intent\":\"{s}\",\"selected_model\":\"{s}\",\"provider\":\"{s}\",\"score\":{d:.6},\"transport\":\"{s}\",\"http_status\":{s},\"body_digest\":{s},\"text_preview\":{f},\"google_key\":{},\"openrouter_key\":{},\"authoritative\":false,\"operational_qualification_claimed\":false,\"plane\":\"platform\"}}\n",
        .{
            @tagName(report.intent),
            report.selected_model,
            @tagName(report.provider),
            report.score,
            report.transport,
            status_txt,
            digest_txt,
            std.json.fmt(report.text_preview, .{}),
            report.google_key,
            report.openrouter_key,
        },
    );
}
