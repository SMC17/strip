//! Strip Verify — continuous credibility checks for CI and pull requests.
//!
//! Complements `zig build verify` (build + tests + proof gates) with
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

    var buffer: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    try writer.print(
        "{{\"schema\":\"strip.verify.v1\",\"category\":\"trust_and_evidence_os\",\"programme_docs_present\":{},\"atmosphere_authoritative\":\"{s}\",\"jsbsim_metric_count\":{d},\"replay_pending_enforced\":{},\"passed\":{}}}\n",
        .{
            programme_docs_present,
            strip.atmosphere.manifest.id,
            metrics.metrics.len,
            !allow_pending,
            !failed,
        },
    );
    return if (failed) 1 else 0;
}
