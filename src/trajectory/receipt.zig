//! Signed assurance receipts over folded trajectories (Experience Ed25519 wire format).

const std = @import("std");
const store_mod = @import("store.zig");
const causal = @import("causal.zig");
const signing = @import("../serialization/signing.zig");
const canonical_json = @import("../serialization/canonical_json.zig");
const flight_seal = @import("../flight_test/flight_seal.zig");

pub const schema_v0 = "strip.trajectory.receipt.v0";
pub const public_key_id_ci = "strip-ci-ed25519";
pub const authority_level = "unit-tested";
pub const authority_evidence_id = "strip-trajectory-fold";

pub const Receipt = struct {
    trajectory_id: []const u8,
    events_folded: usize,
    claims_supported: usize,
    claims_unsupported: usize,
    verifications_passed: usize,
    verifications_failed: usize,
    causal_support_edges: usize,
    causal_contradict_edges: usize,
    content_sha256_hex: [64]u8,
    /// Experience signature object JSON fragment (owned).
    signature_json: []const u8,
    operational_qualification_claimed: bool = false,
};

fn writeAuthority(writer: *std.Io.Writer) !void {
    var auth = try canonical_json.Object.begin(writer);
    try auth.key("evidence_ids");
    try writer.writeByte('[');
    try canonical_json.writeString(writer, authority_evidence_id);
    try writer.writeByte(']');
    try auth.key("level");
    try canonical_json.writeString(writer, authority_level);
    try auth.end();
}

fn writeCausal(writer: *std.Io.Writer, contradict_edges: usize, support_edges: usize) !void {
    var obj = try canonical_json.Object.begin(writer);
    try obj.key("contradict_edges");
    try writer.print("{d}", .{contradict_edges});
    try obj.key("support_edges");
    try writer.print("{d}", .{support_edges});
    try obj.end();
}

/// Canonical body (signature stripped). Keys strictly alphabetical.
fn writeCanonicalBody(writer: *std.Io.Writer, receipt: Receipt) !void {
    var obj = try canonical_json.Object.begin(writer);
    try obj.key("authority");
    try writeAuthority(writer);
    try obj.key("causal");
    try writeCausal(writer, receipt.causal_contradict_edges, receipt.causal_support_edges);
    try obj.key("claims_supported");
    try writer.print("{d}", .{receipt.claims_supported});
    try obj.key("claims_unsupported");
    try writer.print("{d}", .{receipt.claims_unsupported});
    try obj.key("content_sha256");
    try canonical_json.writeString(writer, &receipt.content_sha256_hex);
    try obj.key("cryptographic_proof");
    try writer.writeAll("true");
    try obj.key("events_folded");
    try writer.print("{d}", .{receipt.events_folded});
    try obj.key("operational_qualification_claimed");
    try writer.writeAll("false");
    try obj.key("schema");
    try canonical_json.writeString(writer, schema_v0);
    try obj.key("trajectory_id");
    try canonical_json.writeString(writer, receipt.trajectory_id);
    try obj.key("verification_mode");
    try canonical_json.writeString(writer, "ed25519");
    try obj.key("verifications_failed");
    try writer.print("{d}", .{receipt.verifications_failed});
    try obj.key("verifications_passed");
    try writer.print("{d}", .{receipt.verifications_passed});
    try obj.end();
}

/// Full receipt document with signature inserted in alphabetical key order.
fn writeCanonicalDocument(writer: *std.Io.Writer, receipt: Receipt) !void {
    var obj = try canonical_json.Object.begin(writer);
    try obj.key("authority");
    try writeAuthority(writer);
    try obj.key("causal");
    try writeCausal(writer, receipt.causal_contradict_edges, receipt.causal_support_edges);
    try obj.key("claims_supported");
    try writer.print("{d}", .{receipt.claims_supported});
    try obj.key("claims_unsupported");
    try writer.print("{d}", .{receipt.claims_unsupported});
    try obj.key("content_sha256");
    try canonical_json.writeString(writer, &receipt.content_sha256_hex);
    try obj.key("cryptographic_proof");
    try writer.writeAll("true");
    try obj.key("events_folded");
    try writer.print("{d}", .{receipt.events_folded});
    try obj.key("operational_qualification_claimed");
    try writer.writeAll("false");
    try obj.key("schema");
    try canonical_json.writeString(writer, schema_v0);
    try obj.key("signature");
    try writer.writeAll(receipt.signature_json);
    try obj.key("trajectory_id");
    try canonical_json.writeString(writer, receipt.trajectory_id);
    try obj.key("verification_mode");
    try canonical_json.writeString(writer, "ed25519");
    try obj.key("verifications_failed");
    try writer.print("{d}", .{receipt.verifications_failed});
    try obj.key("verifications_passed");
    try writer.print("{d}", .{receipt.verifications_passed});
    try obj.end();
}

pub fn buildReceipt(
    allocator: std.mem.Allocator,
    store: *const store_mod.Store,
    trajectory_id: []const u8,
    key_pair: signing.Ed25519.KeyPair,
    edge_buf: []causal.Edge,
) !Receipt {
    var graph = causal.Graph.init(edge_buf);
    try graph.build(store);

    var material_buf: [512]u8 = undefined;
    const material = try std.fmt.bufPrint(
        &material_buf,
        "trajectory:{s}:events={d}:claims_ok={d}:claims_bad={d}:v_pass={d}:v_fail={d}:support={d}:contradict={d}",
        .{
            trajectory_id,
            store.state.event_count,
            store.state.claims_supported,
            store.state.claims_unsupported,
            store.state.verifications_passed,
            store.state.verifications_failed,
            graph.claim_support_edges,
            graph.contradict_edges,
        },
    );
    var digest_hex: [64]u8 = undefined;
    flight_seal.digestHexOf(material, &digest_hex);

    var draft: Receipt = .{
        .trajectory_id = trajectory_id,
        .events_folded = store.state.event_count,
        .claims_supported = store.state.claims_supported,
        .claims_unsupported = store.state.claims_unsupported,
        .verifications_passed = store.state.verifications_passed,
        .verifications_failed = store.state.verifications_failed,
        .causal_support_edges = graph.claim_support_edges,
        .causal_contradict_edges = graph.contradict_edges,
        .content_sha256_hex = digest_hex,
        .signature_json = "",
    };

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    defer body_writer.deinit();
    try writeCanonicalBody(&body_writer.writer, draft);
    const exp = try signing.signSha256Payload(key_pair, body_writer.written());

    var sig_buf: [512]u8 = undefined;
    const sig_json = try exp.formatJson(public_key_id_ci, &sig_buf);
    const owned_sig = try allocator.dupe(u8, sig_json);
    draft.signature_json = owned_sig;
    return draft;
}

pub fn formatReceiptJson(allocator: std.mem.Allocator, receipt: Receipt) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try writeCanonicalDocument(&out.writer, receipt);
    try out.writer.writeByte('\n');
    return try out.toOwnedSlice();
}

fn lessThanKey(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn writeSortedJsonValue(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: std.json.Value) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .integer => |i| try writer.print("{d}", .{i}),
        .float => |f| try canonical_json.writeNumber(writer, f),
        .number_string => |s| try writer.writeAll(s),
        .string => |s| try canonical_json.writeString(writer, s),
        .array => |arr| {
            try writer.writeByte('[');
            for (arr.items, 0..) |item, idx| {
                if (idx > 0) try writer.writeByte(',');
                try writeSortedJsonValue(allocator, writer, item);
            }
            try writer.writeByte(']');
        },
        .object => |map| {
            const keys = try allocator.alloc([]const u8, map.count());
            defer allocator.free(keys);
            var ki: usize = 0;
            var it = map.iterator();
            while (it.next()) |entry| : (ki += 1) {
                keys[ki] = entry.key_ptr.*;
            }
            std.mem.sort([]const u8, keys, {}, lessThanKey);

            var obj = try canonical_json.Object.begin(writer);
            for (keys) |k| {
                try obj.key(k);
                try writeSortedJsonValue(allocator, writer, map.get(k).?);
            }
            try obj.end();
        },
    }
}

fn requireString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const v = obj.get(key) orelse return error.MissingField;
    return switch (v) {
        .string => |s| s,
        else => error.InvalidFieldType,
    };
}

fn requireBool(obj: std.json.ObjectMap, key: []const u8, expected: bool) !void {
    const v = obj.get(key) orelse return error.MissingField;
    const b = switch (v) {
        .bool => |x| x,
        else => return error.InvalidFieldType,
    };
    if (b != expected) return error.FieldMismatch;
}

/// Verify an Experience-format receipt: rebuild sorted-key body, check Ed25519 over raw SHA-256.
pub fn verifyExperienceReceiptJson(allocator: std.mem.Allocator, json_bytes: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidReceipt;
    const root = parsed.value.object;

    try requireBool(root, "cryptographic_proof", true);
    try requireBool(root, "operational_qualification_claimed", false);
    const mode = try requireString(root, "verification_mode");
    if (!std.mem.eql(u8, mode, "ed25519")) return error.UnsupportedVerificationMode;
    const schema = try requireString(root, "schema");
    if (!std.mem.eql(u8, schema, schema_v0)) return error.UnexpectedSchema;
    _ = try requireString(root, "trajectory_id");

    const sig_val = root.get("signature") orelse return error.MissingSignature;
    if (sig_val != .object) return error.InvalidSignature;
    const sig = sig_val.object;
    const algorithm = try requireString(sig, "algorithm");
    if (!std.mem.eql(u8, algorithm, "ed25519")) return error.UnsupportedAlgorithm;
    const public_hex = try requireString(sig, "public_key_hex");
    const value_hex = try requireString(sig, "value_hex");
    const payload_hex = try requireString(sig, "payload_sha256_hex");
    _ = try requireString(sig, "public_key_id");
    const status = try requireString(sig, "status");
    if (!std.mem.eql(u8, status, "signed")) return error.UnexpectedSignatureStatus;

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    defer body_writer.deinit();

    const keys = try allocator.alloc([]const u8, root.count());
    defer allocator.free(keys);
    var ki: usize = 0;
    var it = root.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, "signature")) continue;
        keys[ki] = entry.key_ptr.*;
        ki += 1;
    }
    const body_keys = keys[0..ki];
    std.mem.sort([]const u8, body_keys, {}, lessThanKey);

    var obj = try canonical_json.Object.begin(&body_writer.writer);
    for (body_keys) |k| {
        try obj.key(k);
        try writeSortedJsonValue(allocator, &body_writer.writer, root.get(k).?);
    }
    try obj.end();

    const payload = body_writer.written();
    var computed_hex: [64]u8 = undefined;
    flight_seal.digestHexOf(payload, &computed_hex);
    if (!std.mem.eql(u8, &computed_hex, payload_hex)) return error.PayloadHashMismatch;

    try signing.verifySha256Payload(public_hex, value_hex, payload);
}

test "receipt seals reference fold" {
    const jsonl = @import("jsonl.zig");
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/trajectory/reference-uas-atmosphere.jsonl",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var folded = try jsonl.foldJsonl(std.testing.allocator, bytes);
    defer jsonl.freeFold(std.testing.allocator, folded);
    var edge_buf: [64]causal.Edge = undefined;
    const key = try signing.ciKeyPair();
    const receipt = try buildReceipt(std.testing.allocator, &folded.store, "reference-uas-atmosphere", key, &edge_buf);
    defer std.testing.allocator.free(receipt.signature_json);
    try std.testing.expect(receipt.claims_supported >= 1);
    try std.testing.expect(receipt.causal_support_edges >= 1);
    const json = try formatReceiptJson(std.testing.allocator, receipt);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, schema_v0) != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"verification_mode\":\"ed25519\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"public_key_id\":\"strip-ci-ed25519\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "sha256:") == null);
}

test "receipt emit roundtrips Experience verify" {
    const jsonl = @import("jsonl.zig");
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/trajectory/reference-uas-atmosphere.jsonl",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var folded = try jsonl.foldJsonl(std.testing.allocator, bytes);
    defer jsonl.freeFold(std.testing.allocator, folded);
    var edge_buf: [64]causal.Edge = undefined;
    const key = try signing.ciKeyPair();
    const receipt = try buildReceipt(std.testing.allocator, &folded.store, "reference-uas-atmosphere", key, &edge_buf);
    defer std.testing.allocator.free(receipt.signature_json);
    const json = try formatReceiptJson(std.testing.allocator, receipt);
    defer std.testing.allocator.free(json);
    try verifyExperienceReceiptJson(std.testing.allocator, json);
}

test "verify Experience fixture uas-receipt-ed25519" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/experience-receipt/uas-receipt-ed25519.json",
        std.testing.allocator,
        .limited(64 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    try verifyExperienceReceiptJson(std.testing.allocator, bytes);
    // Fixture uses Experience strip-dev key (daaba8ab...), not CI key.
    try std.testing.expect(std.mem.indexOf(u8, bytes, "daaba8ab0153c187cbc289f1440d36d9602cfc51bcb0fd66ecb32bbebac8e277") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, signing.ci_public_hex) == null);
}
