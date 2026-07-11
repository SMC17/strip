//! Typed engineering actions for assurance-carrying agent trajectories.
//!
//! Shell strings are not the primary IR. Actions carry objective, preconditions,
//! expected effects, risk class, and verification requirements.

const std = @import("std");

pub const RiskClass = enum {
    read_only,
    reversible_write,
    simulation,
    evidence_mutation,
    safety_critical,
};

pub const ActionKind = enum {
    read_artifact,
    search_repository,
    run_validation,
    propose_patch,
    seal_flight_package,
    run_campaign,
    assert_claim,
    delegate_task,
    inject_fault,
};

pub const Action = struct {
    kind: ActionKind,
    action_id: []const u8,
    objective: []const u8,
    target: []const u8 = "",
    risk: RiskClass,
    preconditions: []const []const u8 = &.{},
    expected_effects: []const []const u8 = &.{},
    verification: []const []const u8 = &.{},

    pub fn validate(self: Action) !void {
        if (self.action_id.len == 0) return error.MissingActionId;
        if (self.objective.len == 0) return error.MissingObjective;
        if (self.kind == .assert_claim and self.verification.len == 0)
            return error.ClaimRequiresVerificationRefs;
        if (self.kind == .propose_patch and self.target.len == 0)
            return error.PatchRequiresTarget;
        if (self.risk == .safety_critical and self.verification.len == 0)
            return error.SafetyCriticalRequiresVerification;
    }
};

test "claim actions require verification refs" {
    const bad: Action = .{
        .kind = .assert_claim,
        .action_id = "claim-1",
        .objective = "tests pass",
        .risk = .read_only,
    };
    try std.testing.expectError(error.ClaimRequiresVerificationRefs, bad.validate());
}

test "safety-critical actions require verification" {
    const bad: Action = .{
        .kind = .propose_patch,
        .action_id = "patch-1",
        .objective = "change pitch gain",
        .target = "src/control/pid.zig",
        .risk = .safety_critical,
    };
    try std.testing.expectError(error.SafetyCriticalRequiresVerification, bad.validate());
}
