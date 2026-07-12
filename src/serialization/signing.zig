//! Ed25519 attestation for evidence and campaign bundles.
//!
//! Default committed CI keypair is a *development attestation key*. Production
//! deployments override with `STRIP_SIGNING_SEED` (64 hex chars) and publish the
//! matching public key via `STRIP_SIGNING_PUBLIC_KEY` or an updated fixture.
const std = @import("std");

pub const Ed25519 = std.crypto.sign.Ed25519;

pub const Algorithm = enum {
    ed25519,
    unsigned,
};

pub const Signature = struct {
    algorithm: Algorithm,
    public_key_hex: [64]u8,
    signature_hex: [128]u8,
    message_digest_hex: [64]u8,

    pub fn formatJson(self: Signature, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(
            buffer,
            "{{\"algorithm\":\"{s}\",\"public_key\":\"ed25519:{s}\",\"signature\":\"ed25519:{s}\",\"message_digest\":\"sha256:{s}\"}}",
            .{
                @tagName(self.algorithm),
                &self.public_key_hex,
                &self.signature_hex,
                &self.message_digest_hex,
            },
        );
    }
};

pub const ci_seed_hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
pub const ci_public_hex = "207a067892821e25d770f1fba0c47c11ff4b813e54162ece9eb839e076231ab6";

fn hexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHex,
    };
}

pub fn decodeHex(comptime n: usize, hex: []const u8) ![n]u8 {
    if (hex.len != n * 2) return error.InvalidHexLength;
    var out: [n]u8 = undefined;
    for (0..n) |i| {
        const hi = try hexNibble(hex[i * 2]);
        const lo = try hexNibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
    return out;
}

pub fn encodeHex(bytes: []const u8, out: []u8) !void {
    if (out.len < bytes.len * 2) return error.BufferTooSmall;
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        out[i * 2] = alphabet[byte >> 4];
        out[i * 2 + 1] = alphabet[byte & 0x0f];
    }
}

pub fn keyPairFromSeedHex(seed_hex: []const u8) !Ed25519.KeyPair {
    const seed = try decodeHex(32, seed_hex);
    return try Ed25519.KeyPair.generateDeterministic(seed);
}

pub fn ciKeyPair() !Ed25519.KeyPair {
    return keyPairFromSeedHex(ci_seed_hex);
}

pub fn resolveKeyPair(environ: *std.process.Environ.Map) !Ed25519.KeyPair {
    if (environ.get("STRIP_SIGNING_SEED")) |seed| {
        const trimmed = std.mem.trim(u8, seed, " \t\r\n");
        return keyPairFromSeedHex(trimmed);
    }
    return ciKeyPair();
}

pub fn expectedPublicKeyHex(environ: *std.process.Environ.Map) []const u8 {
    if (environ.get("STRIP_SIGNING_PUBLIC_KEY")) |value| {
        return std.mem.trim(u8, value, " \t\r\n");
    }
    return ci_public_hex;
}

pub fn signDigestHex(key_pair: Ed25519.KeyPair, digest_hex: []const u8) !Signature {
    if (digest_hex.len != 64) return error.InvalidDigestHex;
    const sig = try key_pair.sign(digest_hex, null);
    var public_hex: [64]u8 = undefined;
    var sig_hex: [128]u8 = undefined;
    var digest_out: [64]u8 = undefined;
    try encodeHex(&key_pair.public_key.bytes, &public_hex);
    try encodeHex(&sig.toBytes(), &sig_hex);
    @memcpy(&digest_out, digest_hex[0..64]);
    return .{
        .algorithm = .ed25519,
        .public_key_hex = public_hex,
        .signature_hex = sig_hex,
        .message_digest_hex = digest_out,
    };
}

/// Experience AF wire format: Ed25519 over raw SHA-256(payload) bytes (not hex).
pub const ExperienceSig = struct {
    public_key_hex: [64]u8,
    value_hex: [128]u8,
    payload_sha256_hex: [64]u8,

    pub fn formatJson(self: ExperienceSig, public_key_id: []const u8, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(
            buffer,
            "{{\"algorithm\":\"ed25519\",\"payload_sha256_hex\":\"{s}\",\"public_key_hex\":\"{s}\",\"public_key_id\":\"{s}\",\"status\":\"signed\",\"value_hex\":\"{s}\"}}",
            .{
                &self.payload_sha256_hex,
                &self.public_key_hex,
                public_key_id,
                &self.value_hex,
            },
        );
    }
};

fn sha256HexOf(bytes: []const u8, out: *[64]u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    encodeHex(&digest, out) catch unreachable;
    return digest;
}

/// Sign SHA-256(payload_bytes) raw digest with Ed25519 (Experience receipt mode).
pub fn signSha256Payload(key_pair: Ed25519.KeyPair, payload_bytes: []const u8) !ExperienceSig {
    var payload_hex: [64]u8 = undefined;
    const digest = sha256HexOf(payload_bytes, &payload_hex);
    const sig = try key_pair.sign(&digest, null);
    var public_hex: [64]u8 = undefined;
    var value_hex: [128]u8 = undefined;
    try encodeHex(&key_pair.public_key.bytes, &public_hex);
    try encodeHex(&sig.toBytes(), &value_hex);
    return .{
        .public_key_hex = public_hex,
        .value_hex = value_hex,
        .payload_sha256_hex = payload_hex,
    };
}

pub fn verifySha256Payload(public_hex: []const u8, value_hex: []const u8, payload_bytes: []const u8) !void {
    var expected_hex: [64]u8 = undefined;
    const digest = sha256HexOf(payload_bytes, &expected_hex);
    const public_bytes = try decodeHex(32, public_hex);
    const sig_bytes = try decodeHex(64, value_hex);
    const public_key = try Ed25519.PublicKey.fromBytes(public_bytes);
    const sig = Ed25519.Signature.fromBytes(sig_bytes);
    try sig.verify(&digest, public_key);
}

/// Convenience: SHA-256 the message, then Experience-sign the raw digest.
pub fn signMessage(key_pair: Ed25519.KeyPair, message: []const u8) !ExperienceSig {
    return signSha256Payload(key_pair, message);
}

pub fn verifyDigestHex(signature: Signature, digest_hex: []const u8) !void {
    if (signature.algorithm != .ed25519) return error.UnsupportedAlgorithm;
    if (!std.mem.eql(u8, &signature.message_digest_hex, digest_hex)) return error.DigestMismatch;
    const public_bytes = try decodeHex(32, &signature.public_key_hex);
    const sig_bytes = try decodeHex(64, &signature.signature_hex);
    const public_key = try Ed25519.PublicKey.fromBytes(public_bytes);
    const sig = Ed25519.Signature.fromBytes(sig_bytes);
    try sig.verify(digest_hex, public_key);
}

pub fn verifyAgainstExpectedPublicKey(signature: Signature, digest_hex: []const u8, expected_public_hex: []const u8) !void {
    try verifyDigestHex(signature, digest_hex);
    if (!std.mem.eql(u8, &signature.public_key_hex, expected_public_hex))
        return error.PublicKeyMismatch;
}

pub fn loadSeedHex(io: std.Io, path: []const u8) ![64]u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(128));
    defer std.heap.page_allocator.free(bytes);
    const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
    if (trimmed.len != 64) return error.InvalidSeedFile;
    var out: [64]u8 = undefined;
    @memcpy(&out, trimmed[0..64]);
    return out;
}

test "ci keypair signs and verifies digest hex" {
    const key_pair = try ciKeyPair();
    const digest = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899";
    const signature = try signDigestHex(key_pair, digest);
    try verifyDigestHex(signature, digest);
    try std.testing.expectError(error.DigestMismatch, verifyDigestHex(signature, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
}

test "ci public key is stable under committed seed" {
    const key_pair = try ciKeyPair();
    var public_hex: [64]u8 = undefined;
    try encodeHex(&key_pair.public_key.bytes, &public_hex);
    try std.testing.expectEqualStrings(ci_public_hex, &public_hex);
}

test "alternate seed produces different public key and verifies" {
    const alt = try keyPairFromSeedHex("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
    const digest = "11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff";
    const signature = try signDigestHex(alt, digest);
    try verifyDigestHex(signature, digest);
    try std.testing.expect(!std.mem.eql(u8, &signature.public_key_hex, ci_public_hex));
    try std.testing.expectError(
        error.PublicKeyMismatch,
        verifyAgainstExpectedPublicKey(signature, digest, ci_public_hex),
    );
}

test "experience sha256 payload signs raw digest bytes" {
    const key_pair = try ciKeyPair();
    const payload = "{\"schema\":\"strip.trajectory.receipt.v0\"}";
    const exp = try signSha256Payload(key_pair, payload);
    try verifySha256Payload(&exp.public_key_hex, &exp.value_hex, payload);
    try std.testing.expectEqualStrings(ci_public_hex, &exp.public_key_hex);
    try std.testing.expectError(
        error.SignatureVerificationFailed,
        verifySha256Payload(&exp.public_key_hex, &exp.value_hex, "{\"tampered\":true}"),
    );
}
