//! Strip Verify — continuous credibility checks for CI and pull requests.
//!
//! Complements `zig build verify` (build + tests + verification gates) with
//! programme-discipline checks that keep the trust/evidence OS thesis honest.

const std = @import("std");
const strip = @import("strip");
fn fileExists(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    file.close(io);
    return true;
}

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    var failed = false;

    const programme_docs = [_][]const u8{ "ROADMAP-1.0.md", "EXPERIMENTAL.md", "docs/CATEGORY.md" };
    var programme_docs_present = true;
    for (programme_docs) |path| {
        if (!fileExists(init.io, path)) programme_docs_present = false;
    }
    if (!programme_docs_present) failed = true;

    // Authoritative atmosphere must be unified under strip.atmosphere (layered US76 default).
    if (!std.mem.eql(u8, strip.atmosphere.manifest.id, "strip.atmosphere.us76-layered")) failed = true;

    // Per-variable JSBSim cross-implementation metrics must be registered.
    const metrics = strip.adapters.jsbsim.crossImplementationMetrics();
    if (metrics.metrics.len < 4) failed = true;

    // Replay manifest must not carry unresolved pending baselines in CI.
    const allow_pending = init.environ_map.get("STRIP_ALLOW_PENDING_REPLAY") != null;
    if (!allow_pending) {
        const replay_bytes = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            "fixtures/validation/replay/rk4-cross-target.json",
            allocator,
            .limited(256 * 1024),
        );
        defer allocator.free(replay_bytes);
        var replay_manifest = try strip.replay.parseManifest(allocator, replay_bytes);
        defer replay_manifest.deinit();
        var pending_count: usize = 0;
        for (replay_manifest.value.cases) |replay_case| {
            if (std.mem.eql(u8, replay_case.status, "pending")) pending_count += 1;
        }
        if (pending_count > 0) failed = true;
    }

    // CI attestation public key must match the committed seed.
    var signing_ok = false;
    const key_pair = strip.serialization.signing.ciKeyPair() catch null;
    if (key_pair) |kp| {
        var public_hex: [64]u8 = undefined;
        strip.serialization.signing.encodeHex(&kp.public_key.bytes, &public_hex) catch {};
        const fixture_bytes = std.Io.Dir.cwd().readFileAlloc(
            init.io,
            "fixtures/signing/ci-public.ed25519.hex",
            allocator,
            .limited(128),
        ) catch null;
        if (fixture_bytes) |bytes| {
            defer allocator.free(bytes);
            const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
            signing_ok = std.mem.eql(u8, trimmed, &public_hex);
        }
        const probe = strip.serialization.signing.signDigestHex(
            kp,
            "0000000000000000000000000000000000000000000000000000000000000000",
        ) catch null;
        if (probe) |signature| {
            strip.serialization.signing.verifyDigestHex(
                signature,
                "0000000000000000000000000000000000000000000000000000000000000000",
            ) catch {
                signing_ok = false;
            };
        } else signing_ok = false;
    }
    if (!signing_ok) failed = true;

    // OpenVSP real-export pin must be present for digest-required CI.
    const openvsp_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "fixtures/validation/openvsp/export-conformance.json",
        allocator,
        .limited(128 * 1024),
    );
    defer allocator.free(openvsp_bytes);
    var openvsp_pin_present = std.mem.indexOf(u8, openvsp_bytes, "openvsp_cmd_mesh_digest") != null;
    openvsp_pin_present = openvsp_pin_present and
        std.mem.indexOf(u8, openvsp_bytes, "sha256:a91b1a0f31bbcf62785b474a599bfe43d7c4cbc37f7b96d3f4ef0ffc039d001d") != null;
    if (!openvsp_pin_present) failed = true;

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.verify.v1\",\"category\":\"trust_and_evidence_os\",\"programme_docs_present\":{},\"atmosphere_authoritative\":\"{s}\",\"jsbsim_metric_count\":{d},\"replay_pending_enforced\":{},\"ed25519_attestation\":{},\"openvsp_cmd_digest_pinned\":{},\"passed\":{}}}\n",
        .{
            programme_docs_present,
            strip.atmosphere.manifest.id,
            metrics.metrics.len,
            !allow_pending,
            signing_ok,
            openvsp_pin_present,
            !failed,
        },
    );
    return if (failed) 1 else 0;
}
