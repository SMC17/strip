//! Seal and verify flight-test evidence packages (Ed25519 over package digest).

const std = @import("std");
const evidence = @import("evidence.zig");
const signing = @import("../serialization/signing.zig");

pub const Package = struct {
    manifest: evidence.Manifest,
    signature: signing.Signature,
    package_dir: []const u8,

    pub fn validate(self: Package) !void {
        try self.manifest.validate();
        try signing.verifyDigestHex(self.signature, self.manifest.package_sha256);
    }
};

pub fn digestHexOf(bytes: []const u8, out: *[64]u8) void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        out[i * 2] = alphabet[byte >> 4];
        out[i * 2 + 1] = alphabet[byte & 0x0f];
    }
}

pub fn sealManifest(
    key_pair: signing.Ed25519.KeyPair,
    manifest: evidence.Manifest,
) !signing.Signature {
    try manifest.validate();
    return signing.signDigestHex(key_pair, manifest.package_sha256);
}

pub fn loadSealedPackage(
    allocator: std.mem.Allocator,
    io: std.Io,
    package_dir: []const u8,
) !struct {
    package: Package,
    manifest_parsed: std.json.Parsed(evidence.Manifest),
    manifest_bytes: []u8,
    attestation_bytes: []u8,
} {
    var path_buf: [512]u8 = undefined;
    const manifest_path = try std.fmt.bufPrint(&path_buf, "{s}/manifest.json", .{package_dir});
    const manifest_bytes = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(1024 * 1024));
    errdefer allocator.free(manifest_bytes);
    var manifest_parsed = try evidence.parseManifest(allocator, manifest_bytes);
    errdefer manifest_parsed.deinit();

    var att_path_buf: [512]u8 = undefined;
    const att_path = try std.fmt.bufPrint(&att_path_buf, "{s}/attestation.json", .{package_dir});
    const attestation_bytes = try std.Io.Dir.cwd().readFileAlloc(io, att_path, allocator, .limited(64 * 1024));
    errdefer allocator.free(attestation_bytes);

    const Attestation = struct {
        algorithm: []const u8,
        public_key: []const u8,
        signature: []const u8,
        message_digest: []const u8,
    };
    var att_parsed = try std.json.parseFromSlice(Attestation, allocator, attestation_bytes, .{
        .ignore_unknown_fields = false,
        .max_value_len = 256,
    });
    defer att_parsed.deinit();
    if (!std.mem.eql(u8, att_parsed.value.algorithm, "ed25519")) return error.UnsupportedAlgorithm;
    const pk = att_parsed.value.public_key;
    const sig = att_parsed.value.signature;
    const digest = att_parsed.value.message_digest;
    if (!std.mem.startsWith(u8, pk, "ed25519:") or pk.len != 8 + 64) return error.InvalidPublicKey;
    if (!std.mem.startsWith(u8, sig, "ed25519:") or sig.len != 8 + 128) return error.InvalidSignature;
    if (!std.mem.startsWith(u8, digest, "sha256:") or digest.len != 7 + 64) return error.InvalidDigest;

    var public_key_hex: [64]u8 = undefined;
    var signature_hex: [128]u8 = undefined;
    var message_digest_hex: [64]u8 = undefined;
    @memcpy(&public_key_hex, pk[8..72]);
    @memcpy(&signature_hex, sig[8..136]);
    @memcpy(&message_digest_hex, digest[7..71]);
    if (!std.mem.eql(u8, &message_digest_hex, manifest_parsed.value.package_sha256))
        return error.DigestMismatch;

    const signature = signing.Signature{
        .algorithm = .ed25519,
        .public_key_hex = public_key_hex,
        .signature_hex = signature_hex,
        .message_digest_hex = message_digest_hex,
    };
    try signing.verifyDigestHex(signature, &message_digest_hex);

    const package = Package{
        .manifest = manifest_parsed.value,
        .signature = signature,
        .package_dir = package_dir,
    };
    try package.validate();
    return .{
        .package = package,
        .manifest_parsed = manifest_parsed,
        .manifest_bytes = manifest_bytes,
        .attestation_bytes = attestation_bytes,
    };
}

test "seal and verify digest attestation" {
    const key = try signing.ciKeyPair();
    const manifest: evidence.Manifest = .{
        .schema = "strip.flight-test-evidence.v1",
        .package_id = "flight-seal-unit-001",
        .created_utc = "2026-07-11T04:00:00Z",
        .test_card_id = "card-001",
        .configuration_id = "config-001",
        .split_policy_id = "split-001",
        .toolchain = "Zig 0.16",
        .artifacts = &.{.{
            .relative_path = "telemetry/run.csv",
            .media_type = "text/csv",
            .bytes = 32,
            .sha256 = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        }},
        .package_sha256 = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        .sealed = true,
        .operational_qualification_claimed = false,
        .limitations = &.{"Unit-test sealed package only."},
    };
    const signature = try sealManifest(key, manifest);
    try signing.verifyDigestHex(signature, manifest.package_sha256);
}
