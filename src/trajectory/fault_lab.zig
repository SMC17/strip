//! Fault-injection laboratory for trajectory robustness.

const std = @import("std");
const events = @import("events.zig");
const store_mod = @import("store.zig");

pub const ScenarioId = enum {
    duplicate_delivery,
    failed_verification_blocks_claim,
    out_of_order_rejected,
    missing_evidence_ref_blocks_claim,
};

pub const ScenarioResult = struct {
    id: ScenarioId,
    passed: bool,
    detail: []const u8,
};

fn emptyStore(events_buf: []events.Event, seen: [][]const u8, vids: [][]const u8, vstat: []events.VerificationStatus) store_mod.Store {
    return store_mod.Store.init(events_buf, seen, vids, vstat);
}

pub fn runScenario(id: ScenarioId) !ScenarioResult {
    var events_buf: [16]events.Event = undefined;
    var seen: [16][]const u8 = undefined;
    var vids: [16][]const u8 = undefined;
    var vstat: [16]events.VerificationStatus = undefined;
    var store = emptyStore(&events_buf, &seen, &vids, &vstat);

    switch (id) {
        .duplicate_delivery => {
            const ev: events.Event = .{
                .sequence = 1,
                .event_id = "e1",
                .kind = .objective_received,
                .delivery_id = "same",
            };
            try store.append(ev);
            try store.append(ev);
            const ok = store.state.unique_deliveries == 1 and store.state.duplicate_deliveries == 1 and store.len == 1;
            return .{ .id = id, .passed = ok, .detail = "duplicate delivery_id is idempotent" };
        },
        .failed_verification_blocks_claim => {
            try store.append(.{
                .sequence = 1,
                .event_id = "v1",
                .kind = .verification_completed,
                .delivery_id = "d1",
                .verification_status = .failed,
            });
            const result = store.append(.{
                .sequence = 2,
                .event_id = "c1",
                .kind = .claim_asserted,
                .delivery_id = "d2",
                .evidence_refs = &.{"v1"},
            });
            const ok = if (result) |_| false else |err| err == error.ClaimUnsupported;
            return .{ .id = id, .passed = ok, .detail = "failed verification cannot support claim" };
        },
        .out_of_order_rejected => {
            try store.append(.{
                .sequence = 5,
                .event_id = "e5",
                .kind = .objective_received,
                .delivery_id = "d5",
            });
            const result = store.append(.{
                .sequence = 4,
                .event_id = "e4",
                .kind = .objective_received,
                .delivery_id = "d4",
            });
            const ok = if (result) |_| false else |err| err == error.NonMonotonicSequence;
            return .{ .id = id, .passed = ok, .detail = "out-of-order sequence rejected" };
        },
        .missing_evidence_ref_blocks_claim => {
            const result = store.append(.{
                .sequence = 1,
                .event_id = "c1",
                .kind = .claim_asserted,
                .delivery_id = "d1",
                .evidence_refs = &.{},
            });
            const ok = if (result) |_| false else |err| err == error.ClaimUnsupported;
            return .{ .id = id, .passed = ok, .detail = "empty evidence_refs cannot support claim" };
        },
    }
}

pub fn runAll() ![4]ScenarioResult {
    return .{
        try runScenario(.duplicate_delivery),
        try runScenario(.failed_verification_blocks_claim),
        try runScenario(.out_of_order_rejected),
        try runScenario(.missing_evidence_ref_blocks_claim),
    };
}

pub fn allPassed(results: []const ScenarioResult) bool {
    for (results) |r| if (!r.passed) return false;
    return true;
}

test "fault lab scenarios all pass" {
    const results = try runAll();
    try std.testing.expect(allPassed(&results));
}
