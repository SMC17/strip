//! OpenRouter chat client (platform plane, non-authoritative).
//!
//! Never invoke from `zig build verify`.

const std = @import("std");
const weathernext = @import("weathernext.zig");

pub const schema = "strip.openrouter.chat.v0";
pub const default_model = "openai/gpt-4.1-mini";
pub const default_endpoint = "https://openrouter.ai/api/v1/chat/completions";

pub const Mode = enum { fixture, live, status };

pub const ChatReport = struct {
    schema: []const u8 = schema,
    mode: Mode,
    plane: []const u8 = "platform",
    authoritative: bool = false,
    operational_qualification_claimed: bool = false,
    model: []const u8,
    api_key_configured: bool,
    http_status: ?u16 = null,
    body_digest: ?[]const u8 = null,
    body_bytes: usize = 0,
    text_preview: []const u8 = "",
    notes: []const u8,
};

pub const fixture_body =
    \\{"choices":[{"message":{"content":"Strip platform fixture: OpenRouter offline stub. Not operational advice."}}],"model":"fixture"}
;

pub fn statusReport(api_key_configured: bool, model: []const u8) ChatReport {
    return .{
        .mode = .status,
        .model = model,
        .api_key_configured = api_key_configured,
        .notes = if (api_key_configured)
            "API key present; call strip-trajectory router --live to POST chat/completions"
        else
            "set OPENROUTER_API_KEY or write ~/.config/openrouter/key",
    };
}

pub fn chatFixture(allocator: std.mem.Allocator, model: []const u8) !struct {
    report: ChatReport,
    digest_owned: []u8,
} {
    const digest = try weathernext.digestHex(allocator, fixture_body);
    return .{
        .report = .{
            .mode = .fixture,
            .model = model,
            .api_key_configured = false,
            .http_status = 200,
            .body_digest = digest,
            .body_bytes = fixture_body.len,
            .text_preview = "Strip platform fixture: OpenRouter offline stub. Not operational advice.",
            .notes = "offline fixture; not a live OpenRouter response",
        },
        .digest_owned = digest,
    };
}

fn extractContentPreview(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const key = "\"content\"";
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, body, search_from, key)) |key_at| {
        var i = key_at + key.len;
        while (i < body.len and (body[i] == ' ' or body[i] == '\t' or body[i] == '\n' or body[i] == '\r')) : (i += 1) {}
        if (i >= body.len or body[i] != ':') {
            search_from = key_at + key.len;
            continue;
        }
        i += 1;
        while (i < body.len and (body[i] == ' ' or body[i] == '\t' or body[i] == '\n' or body[i] == '\r')) : (i += 1) {}
        if (i >= body.len or body[i] != '"') {
            search_from = key_at + key.len;
            continue;
        }
        const from = i + 1;
        var end = from;
        while (end < body.len and body[end] != '"') : (end += 1) {
            if (body[end] == '\\' and end + 1 < body.len) end += 1;
        }
        const slice = body[from..end];
        if (slice.len == 0) {
            search_from = end + 1;
            continue;
        }
        const n = @min(slice.len, 240);
        return try allocator.dupe(u8, slice[0..n]);
    }
    return try allocator.dupe(u8, "");
}

pub fn chatLive(
    io: std.Io,
    allocator: std.mem.Allocator,
    api_key: []const u8,
    model: []const u8,
    prompt: []const u8,
) !struct {
    report: ChatReport,
    digest_owned: []u8,
    body_owned: []u8,
    preview_owned: []u8,
} {
    var payload_list: std.Io.Writer.Allocating = .init(allocator);
    defer payload_list.deinit();
    try payload_list.writer.print(
        "{{\"model\":{f},\"messages\":[{{\"role\":\"user\",\"content\":{f}}}],\"max_tokens\":256}}",
        .{ std.json.fmt(model, .{}), std.json.fmt(prompt, .{}) },
    );
    const payload = payload_list.written();

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    defer body_writer.deinit();

    var auth_buf: [256]u8 = undefined;
    const auth = try std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{api_key});

    const result = try client.fetch(.{
        .location = .{ .url = default_endpoint },
        .method = .POST,
        .payload = payload,
        .response_writer = &body_writer.writer,
        .keep_alive = false,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = auth },
        },
        .extra_headers = &.{
            .{ .name = "HTTP-Referer", .value = "https://github.com/SMC17/strip" },
            .{ .name = "X-Title", .value = "Strip trajectory platform router" },
        },
    });

    const body = try body_writer.toOwnedSlice();
    errdefer allocator.free(body);
    const digest = try weathernext.digestHex(allocator, body);
    errdefer allocator.free(digest);
    const preview = try extractContentPreview(allocator, body);
    return .{
        .report = .{
            .mode = .live,
            .model = model,
            .api_key_configured = true,
            .http_status = @intFromEnum(result.status),
            .body_digest = digest,
            .body_bytes = body.len,
            .text_preview = preview,
            .notes = "platform-plane OpenRouter chat; never simulation truth",
        },
        .digest_owned = digest,
        .body_owned = body,
        .preview_owned = preview,
    };
}

pub fn formatReport(allocator: std.mem.Allocator, report: ChatReport) ![]u8 {
    if (report.body_digest) |digest| {
        return std.fmt.allocPrint(
            allocator,
            "{{\"schema\":\"{s}\",\"mode\":\"{s}\",\"plane\":\"platform\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"model\":\"{s}\",\"api_key_configured\":{},\"http_status\":{d},\"body_digest\":\"{s}\",\"body_bytes\":{d},\"text_preview\":{f},\"notes\":{f}}}\n",
            .{
                report.schema,
                @tagName(report.mode),
                report.model,
                report.api_key_configured,
                report.http_status orelse 0,
                digest,
                report.body_bytes,
                std.json.fmt(report.text_preview, .{}),
                std.json.fmt(report.notes, .{}),
            },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"{s}\",\"mode\":\"{s}\",\"plane\":\"platform\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"model\":\"{s}\",\"api_key_configured\":{},\"http_status\":null,\"body_digest\":null,\"body_bytes\":0,\"text_preview\":\"\",\"notes\":{f}}}\n",
        .{
            report.schema,
            @tagName(report.mode),
            report.model,
            report.api_key_configured,
            std.json.fmt(report.notes, .{}),
        },
    );
}

test "openrouter fixture is non-authoritative" {
    const got = try chatFixture(std.testing.allocator, default_model);
    defer std.testing.allocator.free(got.digest_owned);
    try std.testing.expect(!got.report.authoritative);
}
