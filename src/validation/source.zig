//! Primary-source provenance records. Records describe sources; they do not
//! imply that the referenced material was copied, validated, or redistributed.
const std = @import("std");

pub const SourceRecord = struct {
    id: []const u8,
    title: []const u8,
    publisher: []const u8,
    edition: []const u8,
    version: []const u8,
    url: []const u8,
    license: []const u8,
    retrieved_at: []const u8,
    digest: []const u8,
    digest_scope: DigestScope,
    extraction: []const u8,
    limitations: []const []const u8,

    pub fn validate(self: SourceRecord) !void {
        try bounded(self.id, 1, 96);
        try bounded(self.title, 1, 256);
        try bounded(self.publisher, 1, 128);
        try bounded(self.edition, 1, 96);
        try bounded(self.version, 1, 96);
        try bounded(self.license, 1, 160);
        try bounded(self.extraction, 1, 512);
        if (!std.mem.startsWith(u8, self.url, "https://") or self.url.len > 512)
            return error.InvalidUrl;
        if (!validDate(self.retrieved_at)) return error.InvalidRetrievalDate;
        if (!validDigest(self.digest)) return error.InvalidDigest;
        if (self.digest_scope == .locator_record and !digestMatches(self.url, self.digest))
            return error.DigestMismatch;
        if (self.limitations.len == 0 or self.limitations.len > 16)
            return error.InvalidLimitations;
        for (self.limitations) |limitation| try bounded(limitation, 1, 512);
    }
};

pub const DigestScope = enum {
    source_content,
    locator_record,
    fixture_content,
};

pub const DatasetManifest = struct {
    schema: []const u8,
    records: []const SourceRecord,

    pub fn validate(self: DatasetManifest) !void {
        if (!std.mem.eql(u8, self.schema, "strip.dataset-manifest.v1"))
            return error.UnsupportedSchema;
        if (self.records.len == 0 or self.records.len > 128) return error.InvalidRecordCount;
        for (self.records, 0..) |record, index| {
            try record.validate();
            for (self.records[0..index]) |prior| {
                if (std.mem.eql(u8, prior.id, record.id)) return error.DuplicateSourceId;
            }
        }
    }
};

pub fn parse(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(DatasetManifest) {
    if (bytes.len > 256 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(DatasetManifest, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

fn bounded(value: []const u8, minimum: usize, maximum: usize) !void {
    if (value.len < minimum or value.len > maximum) return error.InvalidTextLength;
}

fn validDigest(value: []const u8) bool {
    if (value.len != 71 or !std.mem.startsWith(u8, value, "sha256:")) return false;
    for (value[7..]) |c| {
        if (!std.ascii.isHex(c) or std.ascii.isUpper(c)) return false;
    }
    return true;
}

fn validDate(value: []const u8) bool {
    if (value.len != 10 or value[4] != '-' or value[7] != '-') return false;
    for (value, 0..) |c, index| {
        if (index == 4 or index == 7) continue;
        if (!std.ascii.isDigit(c)) return false;
    }
    const month = (value[5] - '0') * 10 + value[6] - '0';
    const day = (value[8] - '0') * 10 + value[9] - '0';
    return month >= 1 and month <= 12 and day >= 1 and day <= 31;
}

fn digestMatches(bytes: []const u8, expected: []const u8) bool {
    var raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &raw, .{});
    const alphabet = "0123456789abcdef";
    var actual: [71]u8 = undefined;
    @memcpy(actual[0..7], "sha256:");
    for (raw, 0..) |byte, index| {
        actual[7 + index * 2] = alphabet[byte >> 4];
        actual[7 + index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return std.mem.eql(u8, &actual, expected);
}

test "primary source manifest is typed, bounded, and complete" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "sources/primary-sources.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var parsed = try parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 18), parsed.value.records.len);
}

test "dataset schema fixtures are accepted and rejected semantically" {
    const valid_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/dataset-manifest.valid.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(valid_bytes);
    var valid = try parse(std.testing.allocator, valid_bytes);
    defer valid.deinit();

    const invalid_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/schemas/dataset-manifest.invalid.json",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(invalid_bytes);
    try std.testing.expectError(error.InvalidTextLength, parse(std.testing.allocator, invalid_bytes));
}

test "source rejects placeholder digest" {
    var record: SourceRecord = .{
        .id = "source",
        .title = "Source",
        .publisher = "Publisher",
        .edition = "first",
        .version = "1",
        .url = "https://example.invalid/source",
        .license = "metadata only",
        .retrieved_at = "2026-07-10",
        .digest = "sha256:placeholder",
        .digest_scope = .locator_record,
        .extraction = "No extraction.",
        .limitations = &.{"No validation evidence."},
    };
    try std.testing.expectError(error.InvalidDigest, record.validate());
}
