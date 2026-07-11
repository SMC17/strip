//! Signed assurance receipts over folded trajectories.

const std = @import("std");
const store_mod = @import("store.zig");
const causal = @import("causal.zig");
const signing = @import("../serialization/signing.zig");
const flight_seal = @import("../flight_test/flight_seal.zig");

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
    signature_json: []const u8,
    operational_qualification_claimed: bool = false,
};

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

    const signature = try signing.signDigestHex(key_pair, &digest_hex);
    var sig_buf: [512]u8 = undefined;
    const sig_json = try signature.formatJson(&sig_buf);
    const owned_sig = try allocator.dupe(u8, sig_json);

    return .{
        .trajectory_id = trajectory_id,
        .events_folded = store.state.event_count,
        .claims_supported = store.state.claims_supported,
        .claims_unsupported = store.state.claims_unsupported,
        .verifications_passed = store.state.verifications_passed,
        .verifications_failed = store.state.verifications_failed,
        .causal_support_edges = graph.claim_support_edges,
        .causal_contradict_edges = graph.contradict_edges,
        .content_sha256_hex = digest_hex,
        .signature_json = owned_sig,
    };
}

pub fn formatReceiptJson(allocator: std.mem.Allocator, receipt: Receipt) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{{\"schema\":\"strip.trajectory.receipt.v0\",\"trajectory_id\":\"{s}\",\"events_folded\":{d},\"claims_supported\":{d},\"claims_unsupported\":{d},\"verifications_passed\":{d},\"verifications_failed\":{d},\"causal\":{{\"support_edges\":{d},\"contradict_edges\":{d}}},\"content_sha256\":\"sha256:{s}\",\"signature\":{s},\"operational_qualification_claimed\":false}}\n",
        .{
            receipt.trajectory_id,
            receipt.events_folded,
            receipt.claims_supported,
            receipt.claims_unsupported,
            receipt.verifications_passed,
            receipt.verifications_failed,
            receipt.causal_support_edges,
            receipt.causal_contradict_edges,
            &receipt.content_sha256_hex,
            receipt.signature_json,
        },
    );
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
    try std.testing.expect(std.mem.indexOf(u8, json, "strip.trajectory.receipt.v0") != null);
}
