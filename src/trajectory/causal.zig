//! Causal provenance graph over folded trajectory events.

const std = @import("std");
const events = @import("events.zig");
const store_mod = @import("store.zig");

pub const EdgeKind = enum {
    proposes,
    authorized_by,
    executes,
    observes,
    verifies,
    supports_claim,
    contradicts_claim,
};

pub const Edge = struct {
    kind: EdgeKind,
    from_event_id: []const u8,
    to_event_id: []const u8,
};

pub const Graph = struct {
    edges: []Edge,
    len: usize = 0,
    claim_support_edges: usize = 0,
    contradict_edges: usize = 0,

    pub fn init(buf: []Edge) Graph {
        return .{ .edges = buf };
    }

    fn push(self: *Graph, edge: Edge) !void {
        if (self.len == self.edges.len) return error.CapacityExceeded;
        self.edges[self.len] = edge;
        self.len += 1;
        switch (edge.kind) {
            .supports_claim => self.claim_support_edges += 1,
            .contradicts_claim => self.contradict_edges += 1,
            else => {},
        }
    }

    pub fn build(self: *Graph, store: *const store_mod.Store) !void {
        var last_action: ?[]const u8 = null;
        var last_policy: ?[]const u8 = null;
        var last_exec: ?[]const u8 = null;
        var last_obs: ?[]const u8 = null;

        for (store.slice()) |ev| {
            switch (ev.kind) {
                .action_proposed => {
                    last_action = ev.event_id;
                },
                .policy_evaluated => {
                    if (last_action) |a| {
                        try self.push(.{ .kind = .authorized_by, .from_event_id = a, .to_event_id = ev.event_id });
                    }
                    last_policy = ev.event_id;
                },
                .action_executed => {
                    if (last_action) |a| {
                        try self.push(.{ .kind = .executes, .from_event_id = a, .to_event_id = ev.event_id });
                    }
                    if (last_policy) |p| {
                        try self.push(.{ .kind = .authorized_by, .from_event_id = p, .to_event_id = ev.event_id });
                    }
                    last_exec = ev.event_id;
                },
                .observation_recorded => {
                    if (last_exec) |e| {
                        try self.push(.{ .kind = .observes, .from_event_id = e, .to_event_id = ev.event_id });
                    }
                    last_obs = ev.event_id;
                },
                .verification_completed => {
                    if (last_obs) |o| {
                        try self.push(.{ .kind = .verifies, .from_event_id = o, .to_event_id = ev.event_id });
                    } else if (last_exec) |e| {
                        try self.push(.{ .kind = .verifies, .from_event_id = e, .to_event_id = ev.event_id });
                    }
                },
                .claim_asserted => {
                    for (ev.evidence_refs) |ref| {
                        var status: ?events.VerificationStatus = null;
                        for (store.verif_ids[0..store.verif_len], 0..) |vid, i| {
                            if (std.mem.eql(u8, vid, ref)) {
                                status = store.verif_status[i];
                                break;
                            }
                        }
                        const kind: EdgeKind = if (status == .passed) .supports_claim else .contradicts_claim;
                        try self.push(.{ .kind = kind, .from_event_id = ref, .to_event_id = ev.event_id });
                    }
                },
                else => {},
            }
        }
    }

    pub fn slice(self: *const Graph) []const Edge {
        return self.edges[0..self.len];
    }
};

test "causal graph links verification to claim" {
    var events_buf: [16]events.Event = undefined;
    var seen: [16][]const u8 = undefined;
    var vids: [16][]const u8 = undefined;
    var vstat: [16]events.VerificationStatus = undefined;
    var store = store_mod.Store.init(&events_buf, &seen, &vids, &vstat);

    try store.append(.{ .sequence = 1, .event_id = "a1", .kind = .action_proposed, .delivery_id = "d1" });
    try store.append(.{ .sequence = 2, .event_id = "p1", .kind = .policy_evaluated, .delivery_id = "d2", .policy = .approved });
    try store.append(.{ .sequence = 3, .event_id = "x1", .kind = .action_executed, .delivery_id = "d3" });
    try store.append(.{ .sequence = 4, .event_id = "o1", .kind = .observation_recorded, .delivery_id = "d4" });
    try store.append(.{ .sequence = 5, .event_id = "v1", .kind = .verification_completed, .delivery_id = "d5", .verification_status = .passed });
    try store.append(.{ .sequence = 6, .event_id = "c1", .kind = .claim_asserted, .delivery_id = "d6", .evidence_refs = &.{"v1"} });

    var edge_buf: [32]Edge = undefined;
    var g = Graph.init(&edge_buf);
    try g.build(&store);
    try std.testing.expect(g.claim_support_edges >= 1);
    try std.testing.expectEqual(@as(usize, 0), g.contradict_edges);
}
