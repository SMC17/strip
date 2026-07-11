//! Append-only trajectory event kinds and folded session state.

const std = @import("std");
const action = @import("action.zig");

pub const EventKind = enum {
    trajectory_created,
    objective_received,
    context_attached,
    action_proposed,
    policy_evaluated,
    action_executed,
    observation_recorded,
    verification_completed,
    claim_asserted,
    fault_injected,
    run_completed,
};

pub const PolicyDecision = enum { approved, denied, deferred };

pub const VerificationStatus = enum { passed, failed, skipped, missing };

pub const Event = struct {
    sequence: u64,
    event_id: []const u8,
    kind: EventKind,
    /// Stable identity for idempotent delivery (duplicates with same id are no-ops).
    delivery_id: []const u8,
    /// Optional action payload for proposal/execution events.
    action_ref: ?action.Action = null,
    policy: ?PolicyDecision = null,
    verification_status: ?VerificationStatus = null,
    /// For claim_asserted: event_ids of verification_completed that must have passed.
    evidence_refs: []const []const u8 = &.{},
    detail: []const u8 = "",
};

pub const FoldedState = struct {
    event_count: usize = 0,
    unique_deliveries: usize = 0,
    duplicate_deliveries: usize = 0,
    actions_proposed: usize = 0,
    actions_executed: usize = 0,
    verifications_passed: usize = 0,
    verifications_failed: usize = 0,
    claims_asserted: usize = 0,
    claims_supported: usize = 0,
    claims_unsupported: usize = 0,
    policy_denied: usize = 0,
    completed: bool = false,
    last_sequence: u64 = 0,
};

pub const FoldError = error{
    NonMonotonicSequence,
    CapacityExceeded,
    InvalidAction,
    ClaimUnsupported,
};
