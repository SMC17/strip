//! Gemini API platform-plane client (non-authoritative).
//!
//! Live calls need `GEMINI_API_KEY` or `GOOGLE_API_KEY`.
//! Never invoke from `zig build verify` simulation paths.

const std = @import("std");
const weathernext = @import("weathernext.zig");

pub const schema = "strip.gemini.generate.v0";
pub const default_model = "gemini-2.0-flash";
pub const default_endpoint_prefix = "https://generativelanguage.googleapis.com/v1beta/models/";

pub const Mode = enum { fixture, live, status };

pub const GenerateReport = struct {
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
    \\{"candidates":[{"content":{"parts":[{"text":"Strip platform fixture: Gemini offline stub. Not operational advice."}]}}],"modelVersion":"fixture"}
;

pub fn statusReport(api_key_configured: bool, model: []const u8) GenerateReport {
    return .{
        .mode = .status,
        .model = model,
        .api_key_configured = api_key_configured,
        .notes = if (api_key_configured)
            "API key present; call gemini --live \"prompt\" to POST generateContent"
        else
            "set GEMINI_API_KEY or GOOGLE_API_KEY from https://aistudio.google.com/apikey",
    };
}

pub fn generateFixture(allocator: std.mem.Allocator, model: []const u8) !struct {
    report: GenerateReport,
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
            .text_preview = "Strip platform fixture: Gemini offline stub. Not operational advice.",
            .notes = "offline fixture; not a live Gemini response",
        },
        .digest_owned = digest,
    };
}

fn extractTextPreview(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    // Best-effort: find first "text":"..." value without full JSON tree walk.
    const key = "\"text\":\"";
    if (std.mem.indexOf(u8, body, key)) |start| {
        const from = start + key.len;
        var end = from;
        while (end < body.len and body[end] != '"') : (end += 1) {
            if (body[end] == '\\' and end + 1 < body.len) end += 1;
        }
        const slice = body[from..end];
        const n = @min(slice.len, 160);
        return try allocator.dupe(u8, slice[0..n]);
    }
    return try allocator.dupe(u8, "");
}

pub fn generateLive(
    io: std.Io,
    allocator: std.mem.Allocator,
    api_key: []const u8,
    model: []const u8,
    prompt: []const u8,
) !struct {
    report: GenerateReport,
    digest_owned: []u8,
    body_owned: []u8,
    preview_owned: []u8,
} {
    var url_buf: [512]u8 = undefined;
    const url = try std.fmt.bufPrint(
        &url_buf,
        "{s}{s}:generateContent",
        .{ default_endpoint_prefix, model },
    );

    var payload_list: std.Io.Writer.Allocating = .init(allocator);
    defer payload_list.deinit();
    try payload_list.writer.print(
        "{{\"contents\":[{{\"parts\":[{{\"text\":{f}}}]}}]}}",
        .{std.json.fmt(prompt, .{})},
    );
    const payload = payload_list.written();

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    defer body_writer.deinit();

    var key_header_buf: [256]u8 = undefined;
    const key_header = try std.fmt.bufPrint(&key_header_buf, "{s}", .{api_key});

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = payload,
        .response_writer = &body_writer.writer,
        .keep_alive = false,
        .headers = .{
            .content_type = .{ .override = "application/json" },
        },
        .extra_headers = &.{
            .{ .name = "x-goog-api-key", .value = key_header },
        },
    });

    const body = try body_writer.toOwnedSlice();
    errdefer allocator.free(body);
    const digest = try weathernext.digestHex(allocator, body);
    errdefer allocator.free(digest);
    const preview = try extractTextPreview(allocator, body);
    return .{
        .report = .{
            .mode = .live,
            .model = model,
            .api_key_configured = true,
            .http_status = @intFromEnum(result.status),
            .body_digest = digest,
            .body_bytes = body.len,
            .text_preview = preview,
            .notes = "platform-plane Gemini generateContent; never simulation truth",
        },
        .digest_owned = digest,
        .body_owned = body,
        .preview_owned = preview,
    };
}

pub fn formatReport(allocator: std.mem.Allocator, report: GenerateReport) ![]u8 {
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

test "fixture generate is non-authoritative" {
    const got = try generateFixture(std.testing.allocator, default_model);
    defer std.testing.allocator.free(got.digest_owned);
    try std.testing.expect(!got.report.authoritative);
    try std.testing.expect(!got.report.operational_qualification_claimed);
}
