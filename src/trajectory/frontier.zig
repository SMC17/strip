//! Frontier pack v1 + v2 (router, workers, analogy, world-model, HIL stream).

const std = @import("std");
const aerospace = @import("aerospace.zig");
const analogy = @import("analogy.zig");
const causal = @import("causal.zig");
const counterfactual = @import("counterfactual.zig");
const fault_lab = @import("fault_lab.zig");
const hil_stream = @import("hil_stream.zig");
const jsonl = @import("jsonl.zig");
const memory = @import("memory.zig");
const receipt = @import("receipt.zig");
const router = @import("router.zig");
const scheduler = @import("scheduler.zig");
const signing = @import("../serialization/signing.zig");
const workers = @import("workers.zig");
const world_model = @import("world_model.zig");

pub const Report = struct {
    counterfactual_passed: bool,
    fault_lab_passed: bool,
    aerospace_passed: bool,
    causal_support_edges: usize,
    receipt_sealed: bool,
    memory_classes: usize,
    scheduler_ready: usize,
    router_passed: bool,
    workers_passed: bool,
    analogy_passed: bool,
    world_model_passed: bool,
    hil_stream_passed: bool,
    hil_events: usize,
    passed: bool,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !Report {
    const path = "fixtures/trajectory/reference-uas-atmosphere.jsonl";

    const cf = try counterfactual.comparePolicyDenial(allocator, io, path, 3);
    const faults = try fault_lab.runAll();
    const fault_ok = fault_lab.allPassed(&faults);

    try aerospace.pitchControllerContract().validate();

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024));
    defer allocator.free(bytes);
    var folded = try jsonl.foldJsonl(allocator, bytes);
    defer jsonl.freeFold(allocator, folded);

    var edge_buf: [64]causal.Edge = undefined;
    var graph = causal.Graph.init(&edge_buf);
    try graph.build(&folded.store);

    const key = try signing.ciKeyPair();
    const rec = try receipt.buildReceipt(allocator, &folded.store, "reference-uas-atmosphere", key, &edge_buf);
    defer allocator.free(rec.signature_json);

    try memory.validateEntry(.{
        .class = .normative,
        .id = "no-ops-qual",
        .content_digest_hex = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        .provenance = "docs/TRAJECTORY.md",
    });

    var task_buf: [4]scheduler.Task = undefined;
    var sched = scheduler.Schedule.init(&task_buf);
    try sched.add(.{
        .id = "validate-us76",
        .objective = "US76 coverage",
        .verification = &.{"v-us76"},
    });
    try sched.add(.{
        .id = "seal-receipt",
        .objective = "seal trajectory receipt",
        .dependencies = &.{"validate-us76"},
        .verification = &.{"receipt"},
    });

    const route = try router.selftest();
    try workers.selftestPersist(io);
    const hit = try analogy.selftest();
    _ = hit;
    const wm = try world_model.selftest();
    const hil = try hil_stream.selftest(allocator);
    const hil_unix = try hil_stream.selftestUnix(allocator, io);

    const v1 = cf.passed and fault_ok and graph.claim_support_edges >= 1 and
        rec.claims_supported >= 1 and sched.readyCount() == 1;
    const v2 = std.mem.eql(u8, route.model_id, "strip-trajectory-local") and
        wm.passed and hil.passed and hil_unix.passed;
    const passed = v1 and v2;

    return .{
        .counterfactual_passed = cf.passed,
        .fault_lab_passed = fault_ok,
        .aerospace_passed = true,
        .causal_support_edges = graph.claim_support_edges,
        .receipt_sealed = rec.signature_json.len > 0,
        .memory_classes = std.meta.fields(memory.Class).len,
        .scheduler_ready = sched.readyCount(),
        .router_passed = true,
        .workers_passed = true,
        .analogy_passed = true,
        .world_model_passed = wm.passed,
        .hil_stream_passed = hil.passed,
        .hil_events = hil.events_emitted + hil_unix.events_emitted,
        .passed = passed,
    };
}

test "frontier pack v2 passes" {
    const report = try run(std.testing.allocator, std.testing.io);
    try std.testing.expect(report.passed);
    try std.testing.expect(report.router_passed);
    try std.testing.expect(report.hil_stream_passed);
}
