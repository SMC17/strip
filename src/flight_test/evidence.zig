//! Content-addressed, sealed evidence-package manifests.
const std = @import("std");

pub const Artifact = struct {
    relative_path: []const u8,
    media_type: []const u8,
    bytes: u64,
    sha256: []const u8,

    pub fn validate(self: Artifact) !void {
        if (self.relative_path.len == 0 or self.relative_path.len > 256 or
            self.relative_path[0] == '/' or std.mem.indexOf(u8, self.relative_path, "..") != null)
            return error.InvalidArtifactPath;
        if (self.media_type.len == 0 or self.media_type.len > 96)
            return error.InvalidMediaType;
        if (self.bytes == 0) return error.EmptyArtifact;
        try validateSha256(self.sha256);
    }
};

pub const Manifest = struct {
    schema: []const u8,
    package_id: []const u8,
    created_utc: []const u8,
    test_card_id: []const u8,
    configuration_id: []const u8,
    split_policy_id: []const u8,
    toolchain: []const u8,
    artifacts: []const Artifact,
    package_sha256: []const u8,
    sealed: bool,
    operational_qualification_claimed: bool,
    limitations: []const []const u8,

    pub fn validate(self: Manifest) !void {
        if (!std.mem.eql(u8, self.schema, "strip.flight-test-evidence.v1"))
            return error.UnsupportedSchema;
        inline for (.{ self.package_id, self.test_card_id, self.configuration_id, self.split_policy_id }) |value|
            if (value.len == 0 or value.len > 96) return error.InvalidIdentity;
        if (self.created_utc.len < 20 or self.created_utc.len > 40 or
            self.created_utc[10] != 'T' or self.created_utc[self.created_utc.len - 1] != 'Z')
            return error.InvalidCreationTime;
        if (self.toolchain.len == 0 or self.toolchain.len > 128) return error.InvalidToolchain;
        if (self.artifacts.len == 0 or self.artifacts.len > 4096)
            return error.InvalidArtifactCount;
        for (self.artifacts, 0..) |artifact, index| {
            try artifact.validate();
            for (self.artifacts[0..index]) |prior|
                if (std.mem.eql(u8, prior.relative_path, artifact.relative_path))
                    return error.DuplicateArtifact;
        }
        try validateSha256(self.package_sha256);
        if (!self.sealed) return error.ManifestNotSealed;
        if (self.operational_qualification_claimed) return error.QualificationClaimNotSupported;
        if (self.limitations.len == 0 or self.limitations.len > 32)
            return error.MissingLimitations;
        for (self.limitations) |limitation|
            if (limitation.len == 0 or limitation.len > 512) return error.InvalidLimitation;
    }
};

pub fn parseManifest(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(Manifest) {
    if (bytes.len > 1024 * 1024) return error.InputTooLarge;
    var parsed = try std.json.parseFromSlice(Manifest, allocator, bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 4096,
    });
    errdefer parsed.deinit();
    try parsed.value.validate();
    return parsed;
}

fn validateSha256(value: []const u8) !void {
    if (value.len != 64) return error.InvalidSha256;
    for (value) |character| {
        const valid = (character >= '0' and character <= '9') or
            (character >= 'a' and character <= 'f');
        if (!valid) return error.InvalidSha256;
    }
}

test "evidence manifest is sealed content-addressed and qualification-neutral" {
    const manifest: Manifest = .{
        .schema = "strip.flight-test-evidence.v1",
        .package_id = "flight-test-synthetic-001",
        .created_utc = "2026-07-10T12:00:00Z",
        .test_card_id = "card-fw-doublet-001",
        .configuration_id = "config-synthetic-a",
        .split_policy_id = "split-2026-07-a",
        .toolchain = "Zig 0.16; dependency-free",
        .artifacts = &.{.{
            .relative_path = "telemetry/run-001.csv",
            .media_type = "text/csv",
            .bytes = 128,
            .sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }},
        .package_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        .sealed = true,
        .operational_qualification_claimed = false,
        .limitations = &.{"Synthetic evidence only; no aircraft or regulator evaluation was performed."},
    };
    try manifest.validate();

    const fixture = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "reports/validation/flight-test/synthetic-evidence-manifest.json",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(fixture);
    var parsed = try parseManifest(std.testing.allocator, fixture);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.sealed);
}
