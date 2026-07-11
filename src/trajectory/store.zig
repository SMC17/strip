//! In-memory append-only trajectory store with idempotent delivery and claim audit.

const std = @import("std");
const action_mod = @import("action.zig");
const events = @import("events.zig");

pub const Store = struct {
    events_buf: []events.Event,
    len: usize = 0,
    /// Parallel delivery_id slots for O(n) idempotency (bounded; fine for fixtures).
    seen_ids: [][]const u8,
    seen_len: usize = 0,
    state: events.FoldedState = .{},
    /// Map verification event_id → status for claim audit.
    verif_ids: [][]const u8,
    verif_status: []events.VerificationStatus,
    verif_len: usize = 0,

    pub fn init(
        events_buf: []events.Event,
        seen_ids: [][]const u8,
        verif_ids: [][]const u8,
        verif_status: []events.VerificationStatus,
    ) Store {
        return .{
            .events_buf = events_buf,
            .seen_ids = seen_ids,
            .verif_ids = verif_ids,
            .verif_status = verif_status,
        };
    }

    pub fn append(self: *Store, event: events.Event) events.FoldError!void {
        if (self.len > 0 and event.sequence < self.state.last_sequence)
            return error.NonMonotonicSequence;

        // Idempotent duplicate delivery: same delivery_id → no state mutation.
        for (self.seen_ids[0..self.seen_len]) |id| {
            if (std.mem.eql(u8, id, event.delivery_id)) {
                self.state.duplicate_deliveries += 1;
                return;
            }
        }
        if (self.seen_len == self.seen_ids.len or self.len == self.events_buf.len)
            return error.CapacityExceeded;

        if (event.action_ref) |act| {
            act.validate() catch return error.InvalidAction;
        }

        self.seen_ids[self.seen_len] = event.delivery_id;
        self.seen_len += 1;
        self.events_buf[self.len] = event;
        self.len += 1;
        self.state.event_count += 1;
        self.state.unique_deliveries += 1;
        self.state.last_sequence = event.sequence;

        switch (event.kind) {
            .action_proposed => self.state.actions_proposed += 1,
            .action_executed => self.state.actions_executed += 1,
            .policy_evaluated => {
                if (event.policy == .denied) self.state.policy_denied += 1;
            },
            .verification_completed => {
                const status = event.verification_status orelse .missing;
                if (self.verif_len == self.verif_ids.len) return error.CapacityExceeded;
                self.verif_ids[self.verif_len] = event.event_id;
                self.verif_status[self.verif_len] = status;
                self.verif_len += 1;
                switch (status) {
                    .passed => self.state.verifications_passed += 1,
                    .failed => self.state.verifications_failed += 1,
                    else => {},
                }
            },
            .claim_asserted => {
                self.state.claims_asserted += 1;
                if (try self.claimSupported(event)) {
                    self.state.claims_supported += 1;
                } else {
                    self.state.claims_unsupported += 1;
                    return error.ClaimUnsupported;
                }
            },
            .run_completed => self.state.completed = true,
            else => {},
        }
    }

    fn claimSupported(self: *const Store, event: events.Event) events.FoldError!bool {
        if (event.evidence_refs.len == 0) return false;
        for (event.evidence_refs) |ref| {
            var found = false;
            for (self.verif_ids[0..self.verif_len], 0..) |vid, i| {
                if (!std.mem.eql(u8, vid, ref)) continue;
                found = true;
                if (self.verif_status[i] != .passed) return false;
            }
            if (!found) return false;
        }
        return true;
    }

    pub fn slice(self: *const Store) []const events.Event {
        return self.events_buf[0..self.len];
    }
};

test "duplicate delivery is idempotent" {
    var events_buf: [8]events.Event = undefined;
    var seen: [8][]const u8 = undefined;
    var vids: [8][]const u8 = undefined;
    var vstat: [8]events.VerificationStatus = undefined;
    var store = Store.init(&events_buf, &seen, &vids, &vstat);

    const ev: events.Event = .{
        .sequence = 1,
        .event_id = "e1",
        .kind = .objective_received,
        .delivery_id = "d1",
        .detail = "hold US76",
    };
    try store.append(ev);
    try store.append(ev);
    try std.testing.expectEqual(@as(usize, 1), store.state.unique_deliveries);
    try std.testing.expectEqual(@as(usize, 1), store.state.duplicate_deliveries);
    try std.testing.expectEqual(@as(usize, 1), store.len);
}

test "unsupported claim is rejected" {
    var events_buf: [8]events.Event = undefined;
    var seen: [8][]const u8 = undefined;
    var vids: [8][]const u8 = undefined;
    var vstat: [8]events.VerificationStatus = undefined;
    var store = Store.init(&events_buf, &seen, &vids, &vstat);

    try store.append(.{
        .sequence = 1,
        .event_id = "v1",
        .kind = .verification_completed,
        .delivery_id = "dv1",
        .verification_status = .failed,
    });
    const result = store.append(.{
        .sequence = 2,
        .event_id = "c1",
        .kind = .claim_asserted,
        .delivery_id = "dc1",
        .evidence_refs = &.{"v1"},
        .detail = "atmosphere validated",
    });
    try std.testing.expectError(error.ClaimUnsupported, result);
}
