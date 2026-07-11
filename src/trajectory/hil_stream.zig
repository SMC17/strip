//! Stream HIL bench progression into trajectory JSONL events.

const std = @import("std");
const hil_bench = @import("../flight_test/hil_bench.zig");
const jsonl = @import("jsonl.zig");

pub const StreamReport = struct {
    events_emitted: usize,
    hil_passed: bool,
    fold_passed: bool,
    jsonl_bytes: usize,
    passed: bool,
};

/// Run in-process HIL progression and emit a foldable trajectory narrative.
pub fn streamToJsonl(allocator: std.mem.Allocator, deadline_ns: u64) !struct {
    report: StreamReport,
    jsonl_owned: []u8,
} {
    const prog = try hil_bench.runLocalProgression(allocator, deadline_ns);
    defer {
        allocator.free(prog.records);
        allocator.free(prog.samples_owned);
    }

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    const hil_passed = prog.report.passed and prog.report.actuator_sensor_completed;
    try list.appendSlice(allocator,
        \\{"sequence":0,"event_id":"hil-e0","kind":"trajectory_created","delivery_id":"hil-d0","detail":"hil-stream"}
        \\{"sequence":1,"event_id":"hil-e1","kind":"objective_received","delivery_id":"hil-d1","detail":"Exercise physical_bench_protocol in-process"}
        \\{"sequence":2,"event_id":"hil-e2","kind":"action_proposed","delivery_id":"hil-d2","action":{"kind":"run_hil_protocol","action_id":"a-hil","objective":"HIL progression","target":"physical_bench_protocol","risk":"simulation","verification":["v-hil"]}}
        \\{"sequence":3,"event_id":"hil-e3","kind":"policy_evaluated","delivery_id":"hil-d3","policy":"approved"}
        \\{"sequence":4,"event_id":"hil-e4","kind":"action_executed","delivery_id":"hil-d4","detail":"runLocalProgression"}
        \\
    );

    // One observation per stage record.
    for (prog.records, 0..) |rec, i| {
        const line = try std.fmt.allocPrint(
            allocator,
            "{{\"sequence\":{d},\"event_id\":\"hil-obs-{d}\",\"kind\":\"observation_recorded\",\"delivery_id\":\"hil-d-obs-{d}\",\"detail\":\"stage={s};evidence={s};passed={}\"}}",
            .{ 5 + i, i, i, @tagName(rec.stage), rec.evidence_id, rec.passed() },
        );
        defer allocator.free(line);
        try list.appendSlice(allocator, line);
        try list.append(allocator, '\n');
    }

    const verif_status: []const u8 = if (hil_passed) "passed" else "failed";
    const seq_v = 5 + prog.records.len;
    const vline = try std.fmt.allocPrint(
        allocator,
        "{{\"sequence\":{d},\"event_id\":\"v-hil\",\"kind\":\"verification_completed\",\"delivery_id\":\"hil-d-v\",\"verification_status\":\"{s}\",\"detail\":\"actuator_sensor_completed={}\"}}",
        .{ seq_v, verif_status, prog.report.actuator_sensor_completed },
    );
    defer allocator.free(vline);
    try list.appendSlice(allocator, vline);
    try list.append(allocator, '\n');

    if (hil_passed) {
        const cline = try std.fmt.allocPrint(
            allocator,
            "{{\"sequence\":{d},\"event_id\":\"hil-claim\",\"kind\":\"claim_asserted\",\"delivery_id\":\"hil-d-c\",\"evidence_refs\":[\"v-hil\"],\"detail\":\"HIL protocol progression completed in-process\"}}\n{{\"sequence\":{d},\"event_id\":\"hil-done\",\"kind\":\"run_completed\",\"delivery_id\":\"hil-d-done\",\"detail\":\"hil stream closed\"}}\n",
            .{ seq_v + 1, seq_v + 2 },
        );
        defer allocator.free(cline);
        try list.appendSlice(allocator, cline);
    } else {
        const dline = try std.fmt.allocPrint(
            allocator,
            "{{\"sequence\":{d},\"event_id\":\"hil-done\",\"kind\":\"run_completed\",\"delivery_id\":\"hil-d-done\",\"detail\":\"hil stream closed without claim\"}}\n",
            .{seq_v + 1},
        );
        defer allocator.free(dline);
        try list.appendSlice(allocator, dline);
    }

    const owned = try list.toOwnedSlice(allocator);
    var folded = try jsonl.foldJsonl(allocator, owned);
    defer jsonl.freeFold(allocator, folded);
    const audit = jsonl.auditReport(&folded.store);
    const fold_passed = if (hil_passed) audit.passed else audit.claims_supported == 0;
    const passed = hil_passed and fold_passed and folded.store.state.event_count >= 8;

    return .{
        .report = .{
            .events_emitted = folded.store.state.event_count,
            .hil_passed = hil_passed,
            .fold_passed = fold_passed,
            .jsonl_bytes = owned.len,
            .passed = passed,
        },
        .jsonl_owned = owned,
    };
}

pub fn selftest(allocator: std.mem.Allocator) !StreamReport {
    const result = try streamToJsonl(allocator, 50_000_000);
    defer allocator.free(result.jsonl_owned);
    if (!result.report.passed) return error.HilStreamFailed;
    return result.report;
}

test "hil stream folds into supported claim" {
    const report = try selftest(std.testing.allocator);
    try std.testing.expect(report.passed);
    try std.testing.expect(report.events_emitted >= 8);
}
