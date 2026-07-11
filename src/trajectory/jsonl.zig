//! Parse trajectory JSONL fixtures and run selftest / claim audit.

const std = @import("std");
const action_mod = @import("action.zig");
const events = @import("events.zig");
const store_mod = @import("store.zig");

const ParsedEvent = struct {
    sequence: u64,
    event_id: []const u8,
    kind: []const u8,
    delivery_id: []const u8,
    detail: []const u8 = "",
    policy: ?[]const u8 = null,
    verification_status: ?[]const u8 = null,
    evidence_refs: []const []const u8 = &.{},
    action: ?struct {
        kind: []const u8,
        action_id: []const u8,
        objective: []const u8,
        target: []const u8 = "",
        risk: []const u8,
        verification: []const []const u8 = &.{},
    } = null,
};

fn parseKind(text: []const u8) !events.EventKind {
    inline for (std.meta.fields(events.EventKind)) |field| {
        if (std.mem.eql(u8, text, field.name)) return @field(events.EventKind, field.name);
    }
    return error.UnknownEventKind;
}

fn parseActionKind(text: []const u8) !action_mod.ActionKind {
    inline for (std.meta.fields(action_mod.ActionKind)) |field| {
        if (std.mem.eql(u8, text, field.name)) return @field(action_mod.ActionKind, field.name);
    }
    return error.UnknownActionKind;
}

fn parseRisk(text: []const u8) !action_mod.RiskClass {
    inline for (std.meta.fields(action_mod.RiskClass)) |field| {
        if (std.mem.eql(u8, text, field.name)) return @field(action_mod.RiskClass, field.name);
    }
    return error.UnknownRiskClass;
}

fn parsePolicy(text: []const u8) !events.PolicyDecision {
    inline for (std.meta.fields(events.PolicyDecision)) |field| {
        if (std.mem.eql(u8, text, field.name)) return @field(events.PolicyDecision, field.name);
    }
    return error.UnknownPolicy;
}

fn parseVerification(text: []const u8) !events.VerificationStatus {
    inline for (std.meta.fields(events.VerificationStatus)) |field| {
        if (std.mem.eql(u8, text, field.name)) return @field(events.VerificationStatus, field.name);
    }
    return error.UnknownVerificationStatus;
}

pub const AuditReport = struct {
    events_folded: usize,
    unique_deliveries: usize,
    duplicate_deliveries: usize,
    claims_supported: usize,
    claims_unsupported: usize,
    verifications_passed: usize,
    verifications_failed: usize,
    completed: bool,
    passed: bool,
};

pub fn foldJsonl(allocator: std.mem.Allocator, bytes: []const u8) !struct {
    store: store_mod.Store,
    // Owned backing so caller can free via deinit pattern — we keep arenas simple:
    // caller owns `bytes`; parsed strings point into JSON arena via Parsed slices.
    // For fixture selftest we allocate event copies into provided buffers.
    events_buf: []events.Event,
    seen: [][]const u8,
    vids: [][]const u8,
    vstat: []events.VerificationStatus,
    parsed: std.json.Parsed([]ParsedEvent),
} {
    // JSONL → JSON array for std.json
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    try list.append(allocator, '[');
    var first = true;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (!first) try list.append(allocator, ',');
        first = false;
        try list.appendSlice(allocator, trimmed);
    }
    try list.append(allocator, ']');

    var parsed = try std.json.parseFromSlice([]ParsedEvent, allocator, list.items, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    errdefer parsed.deinit();

    const n = parsed.value.len;
    const events_buf = try allocator.alloc(events.Event, n + 4);
    errdefer allocator.free(events_buf);
    const seen = try allocator.alloc([]const u8, n + 4);
    errdefer allocator.free(seen);
    const vids = try allocator.alloc([]const u8, n + 4);
    errdefer allocator.free(vids);
    const vstat = try allocator.alloc(events.VerificationStatus, n + 4);
    errdefer allocator.free(vstat);

    var store = store_mod.Store.init(events_buf, seen, vids, vstat);
    for (parsed.value) |pe| {
        var act: ?action_mod.Action = null;
        if (pe.action) |a| {
            act = .{
                .kind = try parseActionKind(a.kind),
                .action_id = a.action_id,
                .objective = a.objective,
                .target = a.target,
                .risk = try parseRisk(a.risk),
                .verification = a.verification,
            };
        }
        const ev: events.Event = .{
            .sequence = pe.sequence,
            .event_id = pe.event_id,
            .kind = try parseKind(pe.kind),
            .delivery_id = pe.delivery_id,
            .action_ref = act,
            .policy = if (pe.policy) |p| try parsePolicy(p) else null,
            .verification_status = if (pe.verification_status) |v| try parseVerification(v) else null,
            .evidence_refs = pe.evidence_refs,
            .detail = pe.detail,
        };
        try store.append(ev);
    }
    return .{
        .store = store,
        .events_buf = events_buf,
        .seen = seen,
        .vids = vids,
        .vstat = vstat,
        .parsed = parsed,
    };
}

pub fn freeFold(
    allocator: std.mem.Allocator,
    folded: anytype,
) void {
    folded.parsed.deinit();
    allocator.free(folded.events_buf);
    allocator.free(folded.seen);
    allocator.free(folded.vids);
    allocator.free(folded.vstat);
}

pub fn auditReport(store: *const store_mod.Store) AuditReport {
    const passed = store.state.claims_unsupported == 0 and
        store.state.verifications_failed == 0 and
        store.state.completed and
        store.state.claims_supported > 0;
    return .{
        .events_folded = store.state.event_count,
        .unique_deliveries = store.state.unique_deliveries,
        .duplicate_deliveries = store.state.duplicate_deliveries,
        .claims_supported = store.state.claims_supported,
        .claims_unsupported = store.state.claims_unsupported,
        .verifications_passed = store.state.verifications_passed,
        .verifications_failed = store.state.verifications_failed,
        .completed = store.state.completed,
        .passed = passed,
    };
}

/// Replay fixture, then re-deliver one event to prove idempotency.
pub fn selftest(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !AuditReport {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024));
    defer allocator.free(bytes);

    var folded = try foldJsonl(allocator, bytes);
    defer freeFold(allocator, folded);

    // Fault inject: duplicate the last unique delivery.
    if (folded.store.len > 0) {
        const last = folded.store.events_buf[folded.store.len - 1];
        try folded.store.append(last);
    }

    return auditReport(&folded.store);
}

test "reference fixture folds and rejects nothing" {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "fixtures/trajectory/reference-uas-atmosphere.jsonl",
        std.testing.allocator,
        .limited(256 * 1024),
    );
    defer std.testing.allocator.free(bytes);
    var folded = try foldJsonl(std.testing.allocator, bytes);
    defer freeFold(std.testing.allocator, folded);
    const report = auditReport(&folded.store);
    try std.testing.expect(report.passed);
    try std.testing.expect(report.claims_supported >= 1);
}
