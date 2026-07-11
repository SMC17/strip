//! WeatherNext platform-plane client (non-authoritative).
//!
//! Never call from `zig build verify` simulation/assurance paths. Live HTTP
//! requires `STRIP_WEATHERNEXT_ENDPOINT` (+ optional `STRIP_WEATHERNEXT_TOKEN`).

const std = @import("std");

pub const schema = "strip.weathernext.fetch.v0";

pub const Mode = enum {
    fixture,
    live,
    status,
};

pub const FetchReport = struct {
    schema: []const u8 = schema,
    mode: Mode,
    plane: []const u8 = "platform",
    authoritative: bool = false,
    operational_qualification_claimed: bool = false,
    endpoint_configured: bool,
    http_status: ?u16 = null,
    body_digest: ?[]const u8 = null,
    body_bytes: usize = 0,
    model_family: []const u8 = "WeatherNext 2",
    notes: []const u8,
};

pub const fixture_body =
    \\{"model":"weathernext-2","forecast_type":"ensemble_mean","lead_hours":24,"variables":["2m_temperature","10m_u_component_of_wind","10m_v_component_of_wind","mean_sea_level_pressure"],"authoritative":false}
;

pub fn digestHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    const out = try allocator.alloc(u8, 7 + 64);
    @memcpy(out[0..7], "sha256:");
    const hex = "0123456789abcdef";
    for (hash, 0..) |b, i| {
        out[7 + i * 2] = hex[b >> 4];
        out[7 + i * 2 + 1] = hex[b & 0xf];
    }
    return out;
}

pub fn fetchFixture(allocator: std.mem.Allocator) !struct { report: FetchReport, digest_owned: []u8 } {
    const digest = try digestHex(allocator, fixture_body);
    return .{
        .report = .{
            .mode = .fixture,
            .endpoint_configured = false,
            .http_status = 200,
            .body_digest = digest,
            .body_bytes = fixture_body.len,
            .notes = "offline fixture; not Vertex/WeatherLab live data",
        },
        .digest_owned = digest,
    };
}

pub fn statusReport(endpoint_configured: bool) FetchReport {
    return .{
        .mode = .status,
        .endpoint_configured = endpoint_configured,
        .notes = if (endpoint_configured)
            "endpoint configured; call fetch --live to perform HTTP GET"
        else
            "set STRIP_WEATHERNEXT_ENDPOINT for live platform fetch",
    };
}

pub fn fetchLive(
    io: std.Io,
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    token: ?[]const u8,
) !struct { report: FetchReport, digest_owned: []u8, body_owned: []u8 } {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    defer body_writer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = endpoint },
        .method = .GET,
        .response_writer = &body_writer.writer,
        .keep_alive = false,
        .extra_headers = if (token) |t| &.{
            .{ .name = "authorization", .value = t },
        } else &.{},
    });

    const body = try body_writer.toOwnedSlice();
    errdefer allocator.free(body);
    const digest = try digestHex(allocator, body);
    return .{
        .report = .{
            .mode = .live,
            .endpoint_configured = true,
            .http_status = @intFromEnum(result.status),
            .body_digest = digest,
            .body_bytes = body.len,
            .notes = "platform-plane live HTTP; not simulation truth; not OpsSpec weather",
        },
        .digest_owned = digest,
        .body_owned = body,
    };
}

pub fn formatReport(allocator: std.mem.Allocator, report: FetchReport) ![]u8 {
    if (report.body_digest) |digest| {
        return std.fmt.allocPrint(
            allocator,
            "{{\"schema\":\"{s}\",\"mode\":\"{s}\",\"plane\":\"{s}\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"endpoint_configured\":{},\"http_status\":{d},\"body_digest\":\"{s}\",\"body_bytes\":{d},\"model_family\":\"{s}\",\"notes\":\"{s}\"}}\n",
            .{
                report.schema,
                @tagName(report.mode),
                report.plane,
                report.endpoint_configured,
                report.http_status orelse 0,
                digest,
                report.body_bytes,
                report.model_family,
                report.notes,
            },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"{s}\",\"mode\":\"{s}\",\"plane\":\"{s}\",\"authoritative\":false,\"operational_qualification_claimed\":false,\"endpoint_configured\":{},\"http_status\":null,\"body_digest\":null,\"body_bytes\":0,\"model_family\":\"{s}\",\"notes\":\"{s}\"}}\n",
        .{
            report.schema,
            @tagName(report.mode),
            report.plane,
            report.endpoint_configured,
            report.model_family,
            report.notes,
        },
    );
}

test "fixture fetch digests offline body" {
    const got = try fetchFixture(std.testing.allocator);
    defer std.testing.allocator.free(got.digest_owned);
    try std.testing.expect(got.report.mode == .fixture);
    try std.testing.expect(!got.report.authoritative);
    try std.testing.expect(!got.report.operational_qualification_claimed);
    try std.testing.expect(std.mem.startsWith(u8, got.digest_owned, "sha256:"));
}
